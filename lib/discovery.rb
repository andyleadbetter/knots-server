require 'socket'
require 'ipaddr'

class Discovery
	
	def initialize(server)
		Thread.new do
			begin
				@running = true
				multicast_addr = "225.4.5.6"
				port = 1978
				ip =  IPAddr.new(multicast_addr).hton + IPAddr.new("0.0.0.0").hton
				@sock = UDPSocket.new
				@sock.bind(Socket::INADDR_ANY, port)
				if Socket::const_defined?('IP_ADD_MEMBERSHIP')
					@sock.setsockopt(Socket::IPPROTO_IP, Socket::IP_ADD_MEMBERSHIP, ip)
				else
					@sock.setsockopt(Socket::IPPROTO_IP, 12, ip)
				end
				last_response = Time.now
				while @running
					msg, info = @sock.recvfrom(1024)
					server.log("Revealed '#{(server.settings.server_name || "Knots server").gsub("/", "|")}/#{server.settings.webrick_ssl}/#{server.settings.webrick_port}' to #{info[3]}:#{info[1]}", 2)
					if msg.strip == "knots" && Time.now - last_response > 2
						@sock.send("#{(server.settings.server_name || "Knots server").gsub("/", "|")}/#{server.settings.webrick_ssl}/#{server.settings.webrick_port}", 0, info[3], info[1])
						last_response = Time.now
					end
				end
			rescue Exception => e
				server.log(e.message)
			end
		end
	end
	
	def stop
		@sock.close
		@running = false
	end
end
