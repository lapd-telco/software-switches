local mg        = require "moongen"
local memory    = require "memory"
local ts        = require "timestamping"
local device    = require "device"
local stats     = require "stats"
local timer     = require "timer"
local histogram = require "histogram"
local log       = require "log"

function configure(parser)
	parser:description("Generates traffic based on a poisson process with CRC-based rate control.")
	parser:argument("txDev", "Device to transmit from."):args(1):convert(tonumber)
	parser:argument("rxDev", "Device to receive from."):args(1):convert(tonumber)
	--parser:option("-r --rate", "Transmit rate in Mpps."):args(1):default(2):convert(tonumber)
	--parser:option("-s --size", "Packet size in Bytes."):args(1):default(60):convert(tonumber)
end

function master(args)
	local txDev = device.config({port = args.txDev, txQueues = 3, rxQueues = 3})
	local rxDev = device.config({port = args.rxDev, txQueues = 3, rxQueues = 3})

	device.waitForLinks()

	mg.startTask("loadSlave", txDev, rxDev, txDev:getTxQueue(0))
	mg.startTask("loadSlave", txDev, rxDev, txDev:getTxQueue(1))

	mg.waitForTasks()
end

function loadSlave(dev, rxDev, queue)
	local mem = memory.createMemPool(function(buf)
		buf:getEthernetPacket():fill{
			ethDst = "aa:cc:dd:cc:00:01",
			ethType = 0x1234
		}
	end)

	local bufs = mem:bufArray()

	if queue.qid == 0
	then
		rxStats= stats:newDevRxCounter(rxDev, "plain")
	end

	local txStats = stats:newManualTxCounter(dev, "plain")
    local limiter = timer:new(20)

	local rates = {0.74, 3.72, 7.44, 11.16, 14.88, 11.16, 7.44, 3.72, 0.74}
	local r = 2
	local rate = rates[1]

	while mg.running() do
		bufs:alloc(60)
		
		if limiter:expired()
		then
			print("10s expired, reset the TX rate.")
			limiter:reset()
			if r <= #rates 
			then rate = rates[r] 
			else
				break
			end
			r = r + 1
		end

		for _, buf in ipairs(bufs) do
			-- this script uses Mpps instead of Mbit (like the other scripts)
			--buf:setDelay(poissonDelay(10^10 / 8 / (rate * 10^6) - size - 24))
			buf:setDelay(10^10 / 8 / (rate * 10^6) - 60 - 24)
		end

		txStats:updateWithSize(queue:sendWithDelay(bufs), 60)

		if queue.qid == 0
    	then
			rxStats:update()
		end
	end

	if queue.qid == 0
    then
		rxStats:finalize()
	end

	txStats:finalize()
end

function timerSlave(txQueue, rxQueue, size)
	local timestamper = ts:newTimestamper(txQueue, rxQueue)
	local hist = histogram:new()
	-- wait for a second to give the other task a chance to start
	mg.sleepMillis(1000)
	local rateLimiter = timer:new(0.001)
	while mg.running() do
		rateLimiter:reset()
		hist:update(timestamper:measureLatency(size))
		rateLimiter:busyWait()
	end
	hist:print()
	hist:save("histogram.csv")
end
