require 'erb'
require 'thread'
include WEBrick

class WEBrick::HTTPAuth::BasicAuth
	
	# Override basic auth to use md5
	
	def authenticate(req, res, force = false)
		if force
			challenge(req, res)
		end
		unless basic_credentials = check_scheme(req)
		  challenge(req, res)
		end
		userid, password = basic_credentials.unpack("m*")[0].split(":", 2) 
		password = password ? Digest::MD5.hexdigest(password) : ""
		if userid.empty?
		  challenge(req, res)
		end
		unless encpass = @userdb.get_passwd(@realm, userid, @reload_db)
		  challenge(req, res)
		end
		if password.crypt(encpass) != encpass
		  challenge(req, res)
		end
		req.user = userid
	      end
end

class String
	def truncate(length)
		if self.size > length
			return self[0, length] + "..."
		end
		self
	end
end




class Plugin < HTTPServlet::AbstractServlet
	
	def initialize(server)
		@server = server
		@cache = Hash.new
		super(server)
	end
	
	def init
	end
	
	def do_POST(req, res)
		server.log(req.unparsed_uri,0,true)
		user = nil
		if @server.auth
			if req.query["switch_user"]
				if !server.force_auth
					server.force_auth = true
					res.set_redirect(WEBrick::HTTPStatus::TemporaryRedirect, "/")
					return
				else
					server.force_auth = false
					user = server.get_user(@server.auth.authenticate(req, res, true))
				end
			end
			user = server.get_user(@server.auth.authenticate(req, res))
		else
			user = OrderHash.new
			user.admin = true
			user.guest = false
			user.role = "admin"
		end
		server.load_plugins if server.settings.devel && server.settings.devel.to_i == 1
		@render = true
		(class << self; self; end).class_eval do
			define_method "params" do
				return req.query
			end
			define_method "request" do 
				return req
			end
			define_method "response" do 
				return res
			end
			define_method "user" do
				return user
			end
		end
		path = request.path[1..request.path.length]
		res["content-type"] = " text/html; charset=utf-8"
		if path.index("/") || path.strip == ""
			method_name = path.split("/")[1]
			method_name = "index" if !method_name || method_name.empty?
		else
			method_name = path
		end
		if !File.extname(method_name) || File.extname(method_name) == "" 
			if method_allowed?(method_name, user.role)
				begin
					method(method_name).call
					if @render
						render(html(method_name))
					end
				rescue Exception => ex
					server.log("Error: #{ex.message}\n#{ex.backtrace.join("\n")}", 0, true)
					render("<h1>#{ex.message}</h1>#{ex.backtrace.join("<br />")}")
				end
			else
				render("You don't have rights to run this action.")
			end
		else
			res["content-type"] = WEBrick::HTTPUtils::DefaultMimeTypes[File.extname(method_name).gsub(".", "")]
			render(load_file(File.join("../all", method_name)))		
		end
	end
	
	def method_allowed?(method_name, role)
		return true
	end
	
	alias :do_GET :do_POST
	
	def enabled
		return true
	end
	
	def image(image, id = nil, options = Hash.new)
		"<img src=\"#{File.join("/", plugin_name, "resource_file?type=image&file=#{image}")}\"#{id ? " id=\"#{id}\"" : ""} border=\"#{options["border"] || 0}\" #{options["width"] ? " width=\"#{options["width"]}\"" : ""}#{options["height"] ? " height=\"#{options["height"]}\"" : ""} />"
	end
	
	def media_screenshot(id, mediatype = nil, width = nil, height = nil, reflection = true, force_reload = true, image_class = nil, mid = nil)
		"<img src=\"#{File.join("/", plugin_name, "resource_file?type=screenshot&#{!mid ? "file=#{id}" : "mid=#{mid}"}&mediatype=#{mediatype || Knots::ITEM_TYPE_VIDEO}")}#{force_reload ? "&rand=#{rand(100000000)}" : ""}\"#{width ? " width=\"#{width}\"" : ""}#{height ? " height=\"#{height}\"" : "media"} #{reflection ? "class=\"reflect rheight10 ropacity33\"" : image_class ? "class=\"#{image_class}\"" : ""} border=\"#{!mid ? "0" : "1"}\" />"
	end
	
	def javascript(script, plugin = plugin_name)
		"<script type=\"text/javascript\" src=\"#{File.join("/", plugin, "resource_file?type=javascript&file=#{script}")}\"></script>"
	end
	
	def stylesheet(file, plugin = plugin_name)
		"<link href=\"#{File.join("/", plugin, "resource_file?type=stylesheet&file=#{file}")}\" media=\"screen\" rel=\"Stylesheet\" type=\"text/css\" />"
	end
	
	def resource_file
		dir = File.basename(params["type"])
		file = File.basename(params["file"]) if params["file"]
		mid = params["mid"]
		type = params["mediatype"]
		if dir != "screenshot"
			response["content-type"] = WEBrick::HTTPUtils::DefaultMimeTypes[File.extname(file).gsub(".", "")]
			render(load_file(File.join("#{dir}s", file)))
		else
			response["content-type"] = "image/jpeg"							
			response["cache-control"] = "max-age=3600, private"
			img = nil
			img = file ? server.database.images.sql("SELECT images.* FROM images,media_images WHERE media_images.media_id=#{file} AND images.id = media_images.image_id").first : db.images.by_id(mid).first
			img = img.image if img
			img = load_file("images/no_shot#{type}.png") if !img
			render(img)
		end
	end
	
	def html(page)
		filename = File.join("htmls", "#{page}#{File.extname(page) == "" ? ".rhtml" : File.extname(page)}")
		page = load_file(filename)
		if page
			@template = ERB.new(page)
			@template.result(binding)
		end
	end
	
	def render(text)
		if @render 
		        #server.log( text, 1, true )     
			response.body = text
			@render = false
		end
	end
	
	def store(key, value)
		server.store(plugin_name, key, value)	
	end
	
	def restore(key)
		server.restore(plugin_name, key)
	end
	
	def load_file(filename)
		[plugin_name, "root"].uniq.each do | path |
			path = File.join("res", path, filename)
			if File.exists?(path)
				return server.load_file(path)
			end
		end
		return nil
	end
	
	def plugin_name
		self.class.name.downcase
	end
	
	def nice_name
		self.class.name
	end
	
	def html_methods
		return {"index" => "index"}
	end
	
	def server
		return @server
	end
	
	def collection
		return server.collection
	end
	
	def database
		return server.database
	end
	
	alias :db :database
end
