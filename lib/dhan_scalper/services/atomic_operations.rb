# frozen_string_literal: true

require_relative '../support/money'

module DhanScalper
  module Services
    # Atomic operations for wallet and position updates using Redis MULTI/EXEC
    class AtomicOperations
      def initialize(redis_store:, balance_provider:, position_tracker:, logger: Logger.new($stdout))
        @redis_store = redis_store
        @balance_provider = balance_provider
        @position_tracker = position_tracker
        @logger = logger
      end

      # Atomic buy operation
      def buy!(exchange_segment:, security_id:, side:, quantity:, price:, fee: nil)
        price_bd = DhanScalper::Support::Money.bd(price)
        quantity_bd = DhanScalper::Support::Money.bd(quantity)
        fee_bd = DhanScalper::Support::Money.bd(fee || DhanScalper::Config.fee)

        # Calculate total cost
        total_cost = DhanScalper::Support::Money.add(
          DhanScalper::Support::Money.multiply(price_bd, quantity_bd),
          fee_bd
        )

        # Check balance before atomic operation
        if @balance_provider.available_balance < total_cost
          return {
            success: false,
            error: "Insufficient balance. Required: ₹#{DhanScalper::Support::Money.dec(total_cost)}, Available: ₹#{DhanScalper::Support::Money.dec(@balance_provider.available_balance)}"
          }
        end

        # Execute atomic operation
        result = execute_atomic do |redis|
          # Debit balance
          debit_balance(redis, total_cost)

          # Update position
          update_position(redis, exchange_segment, security_id, side, quantity_bd, price_bd, fee_bd)
        end

        if result[:success]
          @logger.info("[ATOMIC] Buy executed: #{security_id} | Qty: #{DhanScalper::Support::Money.dec(quantity_bd)} @ ₹#{DhanScalper::Support::Money.dec(price_bd)}")
        end

        result
      end

      # Atomic sell operation
      def sell!(exchange_segment:, security_id:, side:, quantity:, price:, fee: nil)
        price_bd = DhanScalper::Support::Money.bd(price)
        quantity_bd = DhanScalper::Support::Money.bd(quantity)
        fee_bd = DhanScalper::Support::Money.bd(fee || DhanScalper::Config.fee)

        # Get current position
        position = @position_tracker.get_position(
          exchange_segment: exchange_segment,
          security_id: security_id,
          side: side
        )

        unless position && DhanScalper::Support::Money.positive?(position[:net_qty])
          return {
            success: false,
            error: "No position found for #{security_id}"
          }
        end

        # Calculate sellable quantity
        sellable_quantity = DhanScalper::Support::Money.min(quantity_bd, position[:net_qty])

        if DhanScalper::Support::Money.zero?(sellable_quantity)
          return {
            success: false,
            error: "No quantity available to sell for #{security_id}"
          }
        end

        # Execute atomic operation
        result = execute_atomic do |redis|
          # Calculate proceeds and PnL
          gross_proceeds = DhanScalper::Support::Money.multiply(price_bd, sellable_quantity)
          net_proceeds = DhanScalper::Support::Money.subtract(gross_proceeds, fee_bd)
          realized_pnl = DhanScalper::Support::Money.multiply(
            DhanScalper::Support::Money.subtract(price_bd, position[:buy_avg]),
            sellable_quantity
          )

          # Credit balance
          credit_balance(redis, net_proceeds)

          # Update position
          update_position_sell(redis, exchange_segment, security_id, side, sellable_quantity, price_bd, fee_bd)

          # Update realized PnL
          update_realized_pnl(redis, realized_pnl)

          {
            net_proceeds: net_proceeds,
            realized_pnl: realized_pnl,
            sold_quantity: sellable_quantity
          }
        end

        if result[:success]
          @logger.info("[ATOMIC] Sell executed: #{security_id} | Sold: #{DhanScalper::Support::Money.dec(result[:sold_quantity])} @ ₹#{DhanScalper::Support::Money.dec(price_bd)} | PnL: ₹#{DhanScalper::Support::Money.dec(result[:realized_pnl])}")
        end

        result
      end

      # Get current balance atomically
      def get_balance
        execute_atomic do |redis|
          get_balance_from_redis(redis)
        end
      end

      # Get position atomically
      def get_position(exchange_segment:, security_id:, side:)
        execute_atomic do |redis|
          get_position_from_redis(redis, exchange_segment, security_id, side)
        end
      end

      private

      # Execute operations atomically using Redis MULTI/EXEC
      def execute_atomic(&)
        return { success: false, error: 'Redis not available' } unless @redis_store&.redis

        begin
          results = @redis_store.redis.multi(&)

          # MULTI/EXEC returns an array of results
          # For now, assume success if we get here
          { success: true, results: results }
        rescue StandardError => e
          @logger.error("[ATOMIC] Operation failed: #{e.message}")
          { success: false, error: e.message }
        end
      end

      # Debit balance atomically
      def debit_balance(redis, amount)
        balance_key = "#{@redis_store.namespace}:balance"

        # Use Lua script for atomic balance update
        lua_script = <<~LUA
          local balance_key = KEYS[1]
          local amount = tonumber(ARGV[1])

          local current_balance = redis.call('HGET', balance_key, 'available')
          if not current_balance then
            return {err = 'Balance not found'}
          end

          local new_balance = tonumber(current_balance) - amount
          if new_balance < 0 then
            return {err = 'Insufficient balance'}
          end

          redis.call('HSET', balance_key, 'available', new_balance)
          redis.call('HINCRBYFLOAT', balance_key, 'used', amount)
          redis.call('HSET', balance_key, 'total', new_balance + tonumber(redis.call('HGET', balance_key, 'used')))

          return {ok = new_balance}
        LUA

        result = redis.eval(lua_script, keys: [balance_key], argv: [DhanScalper::Support::Money.dec(amount)])

        if result[0] == 'ok'
          { success: true, balance: DhanScalper::Support::Money.bd(result[1]) }
        else
          { success: false, error: result[1] }
        end
      end

      # Credit balance atomically
      def credit_balance(redis, amount)
        balance_key = "#{@redis_store.namespace}:balance"

        # Use Lua script for atomic balance update
        lua_script = <<~LUA
          local balance_key = KEYS[1]
          local amount = tonumber(ARGV[1])

          local current_balance = redis.call('HGET', balance_key, 'available')
          if not current_balance then
            return {err = 'Balance not found'}
          end

          local new_balance = tonumber(current_balance) + amount
          redis.call('HSET', balance_key, 'available', new_balance)
          redis.call('HINCRBYFLOAT', balance_key, 'used', -amount)
          redis.call('HSET', balance_key, 'total', new_balance + tonumber(redis.call('HGET', balance_key, 'used')))

          return {ok = new_balance}
        LUA

        result = redis.eval(lua_script, keys: [balance_key], argv: [DhanScalper::Support::Money.dec(amount)])

        if result[0] == 'ok'
          { success: true, balance: DhanScalper::Support::Money.bd(result[1]) }
        else
          { success: false, error: result[1] }
        end
      end

      # Update position atomically
      def update_position(redis, exchange_segment, security_id, side, quantity, price, fee)
        position_key = "#{@redis_store.namespace}:position:#{exchange_segment}:#{security_id}:#{side}"

        # Use Lua script for atomic position update
        lua_script = <<~LUA
          local position_key = KEYS[1]
          local quantity = tonumber(ARGV[1])
          local price = tonumber(ARGV[2])
          local fee = tonumber(ARGV[3])

          local current_data = redis.call('HMGET', position_key, 'buy_qty', 'buy_avg', 'net_qty')
          local buy_qty = tonumber(current_data[1]) or 0
          local buy_avg = tonumber(current_data[2]) or 0
          local net_qty = tonumber(current_data[3]) or 0

          -- Calculate new weighted average
          local new_buy_qty = buy_qty + quantity
          local new_buy_avg = (buy_qty * buy_avg + quantity * price) / new_buy_qty
          local new_net_qty = net_qty + quantity

          -- Update position
          redis.call('HMSET', position_key,
            'exchange_segment', ARGV[4],
            'security_id', ARGV[5],
            'side', ARGV[6],
            'buy_qty', new_buy_qty,
            'buy_avg', new_buy_avg,
            'net_qty', new_net_qty,
            'current_price', price,
            'last_updated', ARGV[7]
          )

          redis.call('EXPIRE', position_key, 86400) -- 24 hours TTL

          return {ok = {buy_qty = new_buy_qty, buy_avg = new_buy_avg, net_qty = new_net_qty}}
        LUA

        result = redis.eval(lua_script,
                            keys: [position_key],
                            argv: [
                              DhanScalper::Support::Money.dec(quantity),
                              DhanScalper::Support::Money.dec(price),
                              DhanScalper::Support::Money.dec(fee),
                              exchange_segment,
                              security_id,
                              side,
                              Time.now.to_i
                            ])

        if result[0] == 'ok'
          { success: true, position: result[1] }
        else
          { success: false, error: result[1] }
        end
      end

      # Update position for sell atomically
      def update_position_sell(redis, exchange_segment, security_id, side, quantity, price, fee)
        position_key = "#{@redis_store.namespace}:position:#{exchange_segment}:#{security_id}:#{side}"

        # Use Lua script for atomic position sell update
        lua_script = <<~LUA
          local position_key = KEYS[1]
          local sell_quantity = tonumber(ARGV[1])
          local price = tonumber(ARGV[2])
          local fee = tonumber(ARGV[3])

          local current_data = redis.call('HMGET', position_key, 'net_qty', 'sell_qty', 'sell_avg', 'buy_avg')
          local net_qty = tonumber(current_data[1]) or 0
          local sell_qty = tonumber(current_data[2]) or 0
          local sell_avg = tonumber(current_data[3]) or 0
          local buy_avg = tonumber(current_data[4]) or 0

          -- Check if we have enough quantity to sell
          if net_qty < sell_quantity then
            return {err = 'Insufficient quantity to sell'}
          end

          -- Update quantities
          local new_net_qty = net_qty - sell_quantity
          local new_sell_qty = sell_qty + sell_quantity

          -- Calculate new sell average
          local new_sell_avg = (sell_qty * sell_avg + sell_quantity * price) / new_sell_qty

          -- Update position
          redis.call('HMSET', position_key,
            'net_qty', new_net_qty,
            'sell_qty', new_sell_qty,
            'sell_avg', new_sell_avg,
            'current_price', price,
            'last_updated', ARGV[4]
          )

          redis.call('EXPIRE', position_key, 86400) -- 24 hours TTL

          return {ok = {net_qty = new_net_qty, sell_qty = new_sell_qty, sell_avg = new_sell_avg, buy_avg = buy_avg}}
        LUA

        result = redis.eval(lua_script,
                            keys: [position_key],
                            argv: [
                              DhanScalper::Support::Money.dec(quantity),
                              DhanScalper::Support::Money.dec(price),
                              DhanScalper::Support::Money.dec(fee),
                              Time.now.to_i
                            ])

        if result[0] == 'ok'
          { success: true, position: result[1] }
        else
          { success: false, error: result[1] }
        end
      end

      # Update realized PnL atomically
      def update_realized_pnl(redis, pnl)
        pnl_key = "#{@redis_store.namespace}:realized_pnl"

        redis.hincrbyfloat(pnl_key, 'total', DhanScalper::Support::Money.dec(pnl))
        redis.hset(pnl_key, 'last_updated', Time.now.to_i)
        redis.expire(pnl_key, 86_400) # 24 hours TTL

        { success: true }
      end

      # Get balance from Redis
      def get_balance_from_redis(redis)
        balance_key = "#{@redis_store.namespace}:balance"
        data = redis.hgetall(balance_key)

        if data.empty?
          { success: false, error: 'Balance not found' }
        else
          {
            success: true,
            available: DhanScalper::Support::Money.bd(data['available'] || 0),
            used: DhanScalper::Support::Money.bd(data['used'] || 0),
            total: DhanScalper::Support::Money.bd(data['total'] || 0)
          }
        end
      end

      # Get position from Redis
      def get_position_from_redis(redis, exchange_segment, security_id, side)
        position_key = "#{@redis_store.namespace}:position:#{exchange_segment}:#{security_id}:#{side}"
        data = redis.hgetall(position_key)

        if data.empty?
          { success: false, error: 'Position not found' }
        else
          {
            success: true,
            position: {
              exchange_segment: data['exchange_segment'],
              security_id: data['security_id'],
              side: data['side'],
              buy_qty: DhanScalper::Support::Money.bd(data['buy_qty'] || 0),
              buy_avg: DhanScalper::Support::Money.bd(data['buy_avg'] || 0),
              net_qty: DhanScalper::Support::Money.bd(data['net_qty'] || 0),
              sell_qty: DhanScalper::Support::Money.bd(data['sell_qty'] || 0),
              sell_avg: DhanScalper::Support::Money.bd(data['sell_avg'] || 0),
              current_price: DhanScalper::Support::Money.bd(data['current_price'] || 0)
            }
          }
        end
      end
    end
  end
end
