require 'digest/md5'

class Root < Plugin
	
	def nice_name
		"Main"
	end
	
	def html_methods
		return {"Settings" => "settings", "Edit media" => "videos", "Browse" => "browse", "Status" => "server_status", "Collection" => "manage_collection", "Shares" => "manage_shares", "Update" => "update_database"}
	end
	
	def server_status
	end
	
	def index
	end
	
	def issues
	end
	
	def latest
	end
	
	def videos
	end
	
	def switch_user
	end
	
	def dirbrowser
		@dir = params["dir"] ? CGI::unescape(params["dir"]) : server.settings.latest_path || ENV["HOME"]
		@dir = ENV["HOME"] if !File.exists?(@dir)
		@hidden = params["hidden"] && params["hidden"].to_s.downcase.strip == "true"
		@dir = File.expand_path(@dir)
		@dirs = Array.new
		dirlist = Array.new
		begin
			dirlist = Dir.entries(@dir)
		rescue Exception => ex
		end
		dirlist.sort.each do | file |
			if file != "." && file != ".." && (@hidden || file[0,1] != ".")
				file = File.join(@dir, file)
				if File.directory?(file) && File.readable?(file) && File.readable_real?(file)
					@dirs.push(file)
				end
			end
		end
	end
	
	def browse
		params["view"] = server.settings.show_images || "1" if !params["view"]
		if params["search"] || (params["category"] && (user.admin || user.categories.split(",").include?(params["category"])))
			@page = (params["page"] || 1).to_i
			@items, @pages = params["category"] ? collection.browse_category(params["category"].to_i, params["tag_id"], params["value_id"], @page, params["order"]) : collection.search_items(params["search"], params["category"], nil, nil, params["order"], nil, nil, @page, nil, user)
		end
	end
	
	def browse_by_path
		if params["path"]
			params["path"] = CGI::unescape(params["path"])
			@page = (params["page"] || 1).to_i
			@items, @pages = collection.browse_by_path(params["path"],params["limit"].to_i, @page, params["order"] || "added")
		end
		render(html("browse"))
	end
	
	def change_password
		if params["userid"] && params["password"] && params["role"]
			user = db.users.by_id(params["userid"]).first
			load_auth = false
			load_users = false
			pass = Digest::MD5.hexdigest(params["password"])
			if user
				load_auth = user.pass != pass
				load_users = user.role.to_i != params["role"].to_i
				user.pass = pass
				user.role = params["role"]
				user.save
				server.load_auth if load_auth
				server.load_users if load_users
			end
		end
		render("")
	end
	
	def method_allowed?(method_name, role)
		if role == "guest"
			return !["update_database","settings", "videos", "server_status", "change_password", "users", "manage_collection", "manage_shares"].include?(method_name)
		end
		return true
	end
	
	def users
		if params["delete_user"]
			db.users.delete_id(params["delete_user"])
			db.rights.sql("DELETE FROM rights WHERE user=#{params["delete_user"]}")
			server.load_users
			if db.users.all.length == 0
				server.disable_auth
			end
		elsif params["add_user"]
			if !db.users.by_user("LIKE \"#{params["add_user"]}\"").first
				user = db.users.new
				user.user = params["add_user"]
				user.role = 1
				user.pass = Common.generate_password
				user.save
				server.load_users
				server.load_auth if user.role == 0
			end
		end
		if params["show"]
			if params["add_category"]
				right = db.rights.new
				right.user = params["show"]
				right.category = params["add_category"]
				right.save
				server.load_users
			elsif params["remove_category"]
				rights = db.rights.sql("SELECT * FROM rights WHERE user=#{params["show"]} AND category=#{params["remove_category"]}")
				rights.each do | right |
					right.delete
				end
				server.load_users
			end
			@user = db.users.by_id(params["show"]).first
			@categories = db.categories.sql("SELECT * FROM categories WHERE id IN (SELECT category FROM rights WHERE user=#{params["show"]}) ORDER BY category")
			@all_categories = db.categories.sql("SELECT * FROM categories WHERE id NOT IN (SELECT category FROM rights WHERE user=#{params["show"]}) ORDER BY category")
			@media = db.media.sql("SELECT * FROM media WHERE id IN (SELECT media FROM rights WHERE user=#{params["show"]}) ORDER BY name")
		end
	end
	
	def settings
		if user.admin && params["save"]
			db.settings.all.each do | setting |
				if setting.key != "ffmpeg" && setting.key != "vlc"
					if params[setting.key] && params[setting.key] != setting.value
						setting.value = params[setting.key]
						setting.save
					end
				else
					setting.value = File.exists?(params[setting.key]) ? params[setting.key] : nil
					setting.save
				end
			end
			server.load_settings
			if server.settings.force_auth && server.settings.force_auth.to_i == 1
				server.load_auth
				server.load_users
			end
		end
	end
	
	def options
		if user.admin
			if params["desc"]
				setting = db.settings.by_key("=\"#{params["key"]}\"").first || db.settings.new
				setting.name = params["desc"]
				setting.key = params["key"]
				setting.value = params["value"]
				setting.save
				server.load_settings
			elsif params["reset"]
				database2 = KnotsDB.new(File.join("db", "knots.db"))
				migration = server.settings.migration
				db.settings.clear
				if migration
					set = db.settings.new
					set.key = "migration"
					set.value = migration
					set.save
				end
				database2.settings.all.each do | setting |
					if setting.key != "migration"
						dbfields = setting.fields
						dbfields.delete("id")
						set = db.settings.new
						set.set_fields(dbfields)
						set.save
					end
				end
				Common.detect_apps(db)
				server.load_settings
			end
		end
	end
	
	def dynknots
	end
	
	def manage_shares
	end
	
	def dynknots_register
		if user.admin
			begin
				data = Common.fetch("http://nakkiboso.com/knots2/dynknots.php?action=register&username=#{CGI::escape(params["user"])}&password=#{CGI::escape(params["password"])}&name=#{CGI::escape(server.settings.server_name)}&port=#{CGI::escape(server.settings.webrick_port)}&ssl=#{CGI::escape(server.settings.webrick_ssl.to_i == 0 ? "false" : "true")}").body
				if data && !data.index("ERROR") && data.strip.length == 16
					setting = db.settings.by_key("dynknots_key").first || db.settings.new
					setting.key = "dynknots_key"
					setting.value = data.strip
					setting.save
					update = db.settings.by_key("dynknots_last_update").first || db.settings.new
					update.key = "dynknots_last_update"
					update.value = Time.now.to_f.to_s
					update.save
					server.load_settings
					server.dynknots_update
					sleep 1
					render("<script type=\"text/javascript\">ajaxLoad('dynknotsdiv', 'root', 'dynknots', null);</script>")
					return
				elsif data && data.index("ERROR")
					errorcodes = {
						"ERROR0" => "Please fill all the field.",
						"ERROR1" => "Username is already taken. Please login or create a new account.",
						"ERROR3" => "Login failed.",
						"ERROR99" => "Service database error. Please try again later."
					}
					render("Error: #{errorcodes[data.strip] || data}")
					return
				else
					render("Service is down. Please try again later.")
					return
				end
			rescue Exception => ex
				render("Service is down. Please try again later.")
				return
			end
		end
	end
	
	def new_playlist
		if user.admin && params["plname"]
			playlist = db.playlists.by_name("LIKE \"#{params["plname"]}\"").first || db.playlists.new
			playlist.name = params["plname"]
			playlist.save
		end
	end
	
	def change_share_profile
		if user.admin && params["share"] && params["profile"]
			share = db.shares.by_id(params["share"]).first
			if share
				share.transcoding_profile = params["profile"].to_i != -1 ? params["profile"] : nil
				share.save
			end
		end
	end
	
	def reload_playlists
		data = ""
		db.playlists.all.each do | playlist |
			data += "<option value=\"#{playlist.id}\"#{!params["select_playlist"] || params["select_playlist"] != playlist.name ? "" : " selected=\"selected\""}>#{playlist.name}</option>"
		end
		render(data)
	end
	
	def dynknots_login
		if user.admin
			begin
				data = Common.fetch("http://nakkiboso.com/knots2/dynknots.php?action=login&username=#{CGI::escape(params["user"])}&password=#{CGI::escape(params["password"])}").body
				if data && !data.index("ERROR") && data.strip.length == 16
					setting = db.settings.by_key("dynknots_key").first || db.settings.new
					setting.key = "dynknots_key"
					setting.value = data.strip
					setting.save
					server.load_settings
					server.dynknots_update
					sleep 1
					render("<script type=\"text/javascript\">ajaxLoad('dynknotsdiv', 'root', 'dynknots', null);</script>")
					return
				elsif data && data.index("ERROR")
					errorcodes = {
						"ERROR0" => "Please fill all the field.",
						"ERROR1" => "Username is already taken. Please login or create a new account.",
						"ERROR3" => "Login failed.",
						"ERROR99" => "Service database error. Please try again later."
					}
					render("Error: #{errorcodes[data.strip] || data}")
					return
				else
					render("Service is down. Please try again later.")
					return
				end
			rescue Exception => ex
				render("Service is down. Please try again later. #{ex.message}")
				return
			end
		end
	end
	
	def edit_transcoding_profile
		if user.admin
			if params["add"]
				profile = db.transcoding_profiles.new
				profile.name = params["add"]
				profile.save
				params["open"] = profile.id
			elsif params["del"]
				db.transcoding_profiles.delete_id(params["del"])
			end
			render(html("transcoding"))
		end
	end
	
	def save_transcoding_profile
		if user.admin
			profile = db.transcoding_profiles.by_id(params["id"]).first
			fields = Hash.new
			params.each_pair do | key, value |
				value = nil if value == ""
				fields[key] = value if profile.fields.has_key?(key)
			end
			profile.set_fields(fields)
			profile.save
		end
	end
	
	def reset_transcoding_profiles
		if user.admin
			database2 = KnotsDB.new(File.join("db", "knots.db"))
			db.transcoding_profiles.clear
			database2.transcoding_profiles.all.each do | profile |
				dbfields = profile.fields
				dbfields.delete("id")
				set = db.transcoding_profiles.new
				set.set_fields(dbfields)
				set.save
			end
			render(html("transcoding"))
		end
	end
	
	def reset_virtual_categories
		if user.admin
			database2 = KnotsDB.new(File.join("db", "knots.db"))
			db.virtual_categories.all.each do | category |
				collection.delete_image(category.image_id)
			end
			db.virtual_categories.clear
			database2.virtual_categories.all.each do | category |
				dbfields = category.fields
				dbfields.delete("id")
				set = db.virtual_categories.new
				set.set_fields(dbfields)
				set.save
				image = db.images.by_id(set.image_id).first
				if !image
					image2 = database2.images.by_id(set.image_id).first
					if image2
						set2 = db.images.new
						set2.image = image2.data_to_blob(image2.image)
						set2.save
						set.image_id = set2.id
						set.save
					end
				end
			end
			render(html("virtual"))
		end
	end
	
	def save_virtual_category
		if user.admin
			if !params["del"] && !params["add"]
				category = db.virtual_categories.by_id(params["id"]).first
				category.virtual = params["name"]
				category.search = params["query"]
				category.save
			elsif params["del"]
				category = db.virtual_categories.by_id(params["del"]).first
				if category.image_id
					collection.delete_image(category.image_id)
				end
				db.virtual_categories.delete_id(params["del"])
				render(html("virtual"))
			elsif params["add"]
				category = db.virtual_categories.new
				category.virtual = params["add"]
				category.search = "SELECT media.*,media_images.image_id AS mid FROM media WHERE 1=1"
				category.save
				params["open"] = category.id
				render(html("virtual"))
			end
		end
	end
	
	def show_video
		@item = db.media.sql("SELECT media.*,categories.category AS category_name FROM media LEFT JOIN categories ON media.category = categories.id WHERE media.id=#{params["id"]}").first
	end
	
	def show_item_tags
		@item = collection.get_item(params["id"].to_i)
		render(html("taglist"))
	end
	
	def fetch_lyrics
		@lyrics = collection.lyrics_for_item(params["id"].to_i)
	end
	
	def delete_item
		collection.deactivate_item(params["id"].to_i) if user.admin
	end
	
	def themoviedb
		if user.admin
			if !params["saveid"]
				if !params["movieid"]
					@item = collection.get_item(params["id"])
					@info = collection.fetch_movie_info(params["search"] || @item.name)
				else
					@info = collection.fetch_movie_info(nil, params["movieid"])
				end
			else
				@item = db.media.by_id(params["saveid"]).first
				params.each_key do | key |
					if key.index("tag_")
						id = key.split("_")[1]
						tag = params["key_#{id}"]
						value = params["value_#{id}"]
						if tag != "short_overview" && tag != "title"
							tag, tag_value = collection.add_tag(tag, value)
							collection.tag(params["saveid"], tag_value.id)
						elsif tag == "title"
							@item.name = value
						else
							@item.info = value
						end
					end
				end
				@item.save
				render("")
			end
		end
	end
	
	def update_category_tag_image
		if user.admin
			@edited = db.get_table(params["type"]).by_id(params["id"]).first
			if @edited
				if params["userfile"]
					image = @edited.image_id ? db.images.by_id(@edited.image_id).first : db.images.new
					image.image = image.data_to_blob(params["userfile"])
					image.save
					if @edited.fields["tag_id"]
						tag = db.tags.by_id(@edited.fields["tag_id"]).first
						if tag
							if tag.tag == "album"
								songs = db.media.sql("SELECT media.* FROM media,media_tags WHERE media_tags.tag_id = #{@edited.id} AND media_tags.media_id = media.id")
								songs.each do | song |
									media_image = db.media_images.by_media_id(song.id).first || db.media_images.new
									media_image.media_id = song.id
									media_image.image_id = image.id
									media_image.save
								end
								media_image = db.media_images.by_value_id(@edited.id).first || db.media_images.new
								media_image.media_id = -1
								media_image.value_id = @edited.id
								media_image.image_id = image.id
								media_image.save
								render(html("images"))
								return
							end
						end
					end
					@edited.image_id = image.id
					@edited.save
					
				elsif params["del"]
					collection.delete_image(@edited.image_id)
					@edited.image_id = nil
					@edited.save
				end
			end
			render(html("images"))
		end
	end
	
	def import_playlist
		if user.admin && params["userfile"]
			collection.import_playlist(nil, params["userfile"], nil, params["plcat"]) 
		end
	end
	
	def pvr
		if user.admin
			if params["remove"]
				db.settings.delete_key("=\"#{params["remove"]}\"")
			elsif params["save"]
				i = 1
				while (vdr = db.settings.by_key("=\"#{params["save"]}#{i}\"").first)
					i += 1
				end
				pvr = db.settings.new
				pvr.name = "Settings for #{params["save"]}#{i}"
				pvr.key = "#{params["save"]}#{i}"
				pvr.value = params["settings"]
				pvr.save
				server.load_settings
			end
		end
	end
	
	def test_pvr
		if user.admin
			id = nil
			success = false
			if params["pvr"] != nil && params["settings"]
				tokens = params["settings"].split(",")
				begin
					Timeout.timeout(10) do
						if params["pvr"].to_i == 0
							data = Common.get_vdr_output(server.settings.netcat, tokens[0], tokens[1], "HELP")
							if data && data.join("").index("SVDRP") != nil
								fetched = Common.fetch("http://#{tokens[0]}:#{tokens[2]}/")
								success = fetched.code.to_i == 200
							end
						elsif params["pvr"].to_i == 1
							require 'mysql'
							my = Mysql::new(tokens[0], tokens[1], tokens[2], tokens[3])
							res = my.query("SELECT
										recorded.starttime,
										recorded.category,
										recorded.title,
										recorded.subtitle,
										recorded.basename,
										storagegroup.dirname
									FROM
										recorded,
										storagegroup
									WHERE
										storagegroup.groupname = recorded.recgroup
									ORDER BY
										endtime
									DESC;
								")
							success = true
						elsif params["pvr"].to_i == 2
							url = nil
							if tokens[5].to_i == 1
								url = "http://#{tokens[3]}:#{tokens[4]}@#{tokens[0]}:#{tokens[1]}/?screenWidth=799"
							else
								url = "http://#{tokens[3]}:#{tokens[4]}@#{tokens[0]}:#{tokens[1]}/web/getservices?sRef=1:7:1:0:0:0:0:0:0:0:FROM%20BOUQUET%20%22bouquets.tv%22%20ORDER%20BY%20bouquet"
							end
							resp = Common.fetch(url)
							success = resp.code.to_i == 200
						elsif params["pvr"].to_i == 3
							url = "http://#{tokens[3]}:#{tokens[4]}@#{tokens[0]}:#{tokens[1]}/?screenWidth=799"
							resp = Common.fetch(url, 10, 60)
							success = resp.code.to_i == 200
						end
					end
				rescue Exception => ex
				end
			end
			if success
				render("<p>Connection successful.</p><script type=\"text/javascript\">document.getElementById('save_pvr#{params["pvr"]}').style.display='inline';</script>")
			else
				render("<p style=\"color:red;\">Connection failed.</p>")
			end
		end
	end
	
	def set_virtual_image
		if user.admin && params["id"]
			@edited = db.virtual_categories.by_id(params["id"]).first
			if @edited
				if params["userfile"]
					image = @edited.image_id ? db.images.by_id(@edited.image_id).first : db.images.new
					image.image = image.data_to_blob(params["userfile"])
					image.save
					@edited.image_id = image.id
					@edited.save
				end
			end
		end
	end
	
	def reload_virtual_image
		if user.admin
			@edited = db.virtual_categories.by_id(params["id"]).first
			if params["del"]
				collection.delete_image(@edited.image_id)
				@edited.image_id = nil
				@edited.save
			end
			if @edited.image_id
				render(media_screenshot(nil, nil, nil, 40, false, true, nil, @edited.image_id))
			else
				render("No image set.")
			end
		end
	end
	
	def edit_categories
		if user.admin
			if params["add"]
				params["category"] = collection.add_category(params["add"]).id
			elsif params["rename"] && params["rename"].strip != "" && params["rename"].to_i > 1 && params["to"] && params["to"].strip.size > 0
				params["category"] = collection.rename_category(params["rename"].to_i, params["to"]).id
			elsif params["remove"] && params["remove"].strip != "" && params["remove"].to_i > 1
				collection.remove_category(params["remove"].to_i)
			end
			render(html("categories"))
		end
	end
	
	def edit_tags
		if user.admin
			if params["add"]
				params["selected"] = collection.add_tag(params["add"]).id
			elsif params["rename"] && params["rename"].strip != "" && params["rename"].to_i > -1 && params["to"] && params["to"].strip.length > 0
				params["selected"] = collection.rename_tag(params["rename"], params["to"]).id
			elsif params["remove"] && params["remove"].strip != "" && params["remove"].to_i > -1
				tag = collection.remove_tag(params["remove"])
			elsif params["tag"] && params["value"] && params["value"].strip != "" && params["value"].to_i > -1
				tag_value = collection.add_tag_value(params["tag"], params["value"])
				params["selected"] = tag_value.tag_id
				params["selected_value"] = tag_value.id
			elsif params["rename_value"] && params["rename_value"].strip != "" && params["rename_value"].to_i > -1 && params["to"] && params["to"].strip.length > 0
				tag_value = collection.rename_tag_value(params["rename_value"], params["to"])
				params["selected"] = tag_value.tag_id
				params["selected_value"] = tag_value.id
			elsif params["remove_value"] && params["remove_value"].strip != "" && params["remove_value"].to_i > -1
				collection.remove_tag_value(params["remove_value"])
			end
			render(html("tags"))
		end
	end
	
	def add_tag_value_to_media
		if user.admin && params["edit"] && params["tag"] && params["tag_value"]
			tag = collection.add_tag(params["tag"])
			value = collection.add_tag_value(tag.id, params["tag_value"])
			collection.tag(params["edit"], value.id)
			@item = collection.get_item(params["edit"])
			render(html("taglist"))
		end
	end
	
	def remove_tag_value_from_media
		if user.admin && params["mediatag_id"]
			collection.remove_tag_value_from_media(params["mediatag_id"])
		end
		@item = collection.get_item(params["edit"])
		render(html("taglist"))
	end
	
	def save_profile
		if user.admin
			profile = db.settings.by_key("=\"transcoding_profile\"").first
			if !profile
				profile = db.settings.new
				profile.key = "transcoding_profile"
			end
			profile.value = params["id"]
			profile.save
			server.load_settings
		end
	end
	
	def search_videos
		ignore = params["ignore"] == "true"
		@items, @count = collection.search_items(params["search"], !ignore ? params["category"] : nil, !ignore ? params["tag"] : nil, !ignore ? params["tag_value"] : nil, params["order"] || "name", params["search_limit"].to_i, nil)
		render(html("videoitems"))
	end
	
	def path_categories
		if params["id"]
			@path = db.scanned.by_id(params["id"]).first
			@categories = db.categories.all
		else
			path = db.scanned.by_id(params["path_id"]).first
			if params["type"].to_i == 0
				path.video_category = params["category"]
			elsif params["type"].to_i == 1
				path.audio_category = params["category"]
			elsif params["type"].to_i == 2
				path.image_category = params["category"]
			end
			path.save 
			render("")
		end
	end
	
	def random_videos
		params["view"] = 1
		params["search"] = ""
		@items = db.media.sql("SELECT * FROM media ORDER BY RANDOM() LIMIT #{server.settings.pageitems}")
		@pages = @items.size
		@page = 1
		render(html("browse"))
	end
	
	def add_to_playlist
		if user.admin && params["id"] && params["playlist"]
			order_by = db.playlist_items.sql("SELECT MAX(order_by) AS order_by FROM playlist_items WHERE playlist_id=#{params["playlist"]} LIMIT 1").first
			order_by = order_by ? order_by.order_by.to_i + 1 : 1
			item = db.playlist_items.new
			item.playlist_id = params["playlist"]
			collection.reset_playlist(item.playlist_id)
			item.media_id = params["id"]
			item.order_by = order_by
			item.save
		end
	end
	
	def playlist
		if user.admin
			@playlist = db.playlists.by_id(params["id"]).first
			@items = db.media.sql("SELECT playlist_items.id AS pid, media.* FROM playlist_items LEFT JOIN media ON playlist_items.media_id = media.id WHERE playlist_id=#{params["id"]} ORDER BY order_by")
		end
	end
	
	def sort_playlist
		params["data"].split("&").each_with_index do | param, i |
			item = db.playlist_items.by_id(param.split("=")[1].to_i).first
			if i == 1
				collection.reset_playlist(item.playlist_id)
			end
			item.order_by = i
			item.save
		end
	end
	
	def delete_playlist
		if user.admin
			db.playlists.delete_id(params["id"])
			db.playlist_items.delete_playlist_id(params["id"])
			db.shares.delete_playlist_id(params["id"])
			render("<script type=\"text/javascript\">closeLightbox();</script>")
		end
	end
	
	def shuffle_playlist
		if user.admin && params["id"]
			collection.shuffle_playlist(params["id"])
			@playlist = db.playlists.by_id(params["id"]).first
			@items = db.media.sql("SELECT playlist_items.id AS pid, media.* FROM playlist_items LEFT JOIN media ON playlist_items.media_id = media.id WHERE playlist_id=#{params["id"]} ORDER BY order_by")
			render(html("playlist"))
		end
		render("")
	end
	
	def save_playlist
		if user.admin
			playlist = db.playlists.by_name("=\"#{params["name"]}\"").first
			if !playlist
				if params["id"].to_i != 1
					db.playlists.delete_id(params["id"])
				end
				playlist = db.playlists.new
				playlist.name = params["name"]
				playlist.save
			else
				collection.reset_playlist(params["id"])
			end
			if playlist.id.to_i != params["id"].to_i
				items = db.playlist_items.by_playlist_id(params["id"])
				items.each do | item |
					item.playlist_id = playlist.id
					item.save
				end
			end
			@playlist = db.playlists.by_id(playlist.id).first
			@items = db.media.sql("SELECT playlist_items.id AS pid, media.* FROM playlist_items LEFT JOIN media ON playlist_items.media_id = media.id WHERE playlist_id=#{playlist.id} ORDER BY order_by")
			render(html("playlist"))
		end
	end
	
	def apply
		ids = Array.new
		params.each_pair do | key, param |
			if key.index("check_")
				ids.push(key.split("_")[1].to_i)
			end
		end
		if ids.size > 0
			method(params["actions"]).call(ids, params)
		end
	end
	
	def rate
		if user.admin
			@item = collection.rate_item(params["id"].to_i, params["rating"].to_i)
		else
			@item = collection.get_item(params["id"].to_i)
		end
		render(html("rating"))
	end
	
	def reload_item
		@item = collection.get_item(params["id"].to_i)
		if !server.settings.show_images || server.settings.show_images.to_i == 1
			params["force"] = true
			render(html("item"))
		else
			render(html("list_item_info"))
		end
	end
	
	def save_item
		if user.admin
			@item = collection.update_item(params["id"].to_i, {
				"name" => params["name"],
				"duration" => params["duration"] ? Common.ffmpeg_position_to_position(params["duration"]) : nil,
				"aspect" => params["aspect"],
				"width" => params["width"],
				"height" => params["height"],
				"updated" => Time.now,
				"info" => params["info"],
				"category" => params["category"],
				"lyrics" => params["lyrics"] && !params["lyrics"].empty? ? params["lyrics"] : nil,
				"path" => params["path"],
				"params" => params["params"] && !params["params"].empty? ? params["params"] : nil
			})
			render(html("show_video"))
		end
	end
	
	def set_category(ids, params)
		if user.admin && params["categories"] && params["categories"].to_i > -1
			items = db.media.sql("SELECT id,category FROM media WHERE id IN (#{ids.join(",")})")
			items.each do | item |
				item.category = params["categories"]
				item.save
			end
		end
	end
	
	def manage_collection
	end
	
	def media
		if user.admin
			if params["rmdir"]
				collection.remove_scan_path(params["rmdir"].to_i)
			elsif params["adddir"]
				collection.add_scan_path(CGI::unescape(params["adddir"]))
			end
		end
		render(html("media"))
	end
	
	def set_tag(ids, params)
		if user.admin && params["tag_values"] && params["tag_values"].to_i > -1
			ids.each do | id |
				collection.tag(id, params["tag_values"])
			end
		end
	end
	
	def deactivate(ids, params)
		if user.admin
			ids.each do | id |
				item = db.media.by_id(id).first
				item.active = 0
				item.save
			end
		end
	end
	
	def custom_screenshot
		if user.admin && params["id"] && params["userfile"]
			item = collection.get_item(params["id"])
			if item
				collection.grab_screenshot_for_item(item.id, nil, nil, params["userfile"])
			end
		end
	end
	
	def update_screenshot
		if user.admin && params["id"]
			item = collection.get_item(params["id"])
			render(media_screenshot(item.id, item.mediatype, nil, nil, false))
		end
	end
	
	def fetch_album_covers
		if user.admin && !server.settings.screenshot || server.settings.screenshot.to_i == 1 
			failures = 0
			albums = db.media.sql("SELECT media.id AS id,media.path AS path FROM media,tags,tag_values,media_tags WHERE media.id NOT IN (SELECT DISTINCT media_id FROM media_images) AND media.mediatype=#{Knots::ITEM_TYPE_AUDIO} AND media_tags.media_id = media.id AND media_tags.tag_id = tag_values.id AND tag_values.tag_id = tags.id AND tags.tag IN ('artist', 'album') GROUP BY tag_values.value")
			albums.each do | item |
				got_image, status = collection.grab_screenshot_for_item(item.id)
				if got_image
					failures = 0
				else
					failures += 1 if status == -1
					if failures == 10
						break
					end
				end
				sleep 0.1
			end
			if failures != 10
				albums = db.media.sql("SELECT media.id,media.path FROM media,tags,tag_values,media_tags WHERE media.id NOT IN (SELECT DISTINCT media_id FROM media_images) AND media.mediatype=#{Knots::ITEM_TYPE_AUDIO} AND media_tags.media_id = media.id AND media_tags.tag_id = tag_values.id AND tag_values.tag_id = tags.id AND tags.tag IN ('artist', 'album') GROUP BY tag_values.value")
				render("Done. Cover missing from #{albums.size} albums.")
			else
				render("There seems to be a problem in the cover service. Try again later.")
			end
		else
			render("Please enable screenshots in settings.")
		end
	end
	
	def fetch_movie_info
		success = 0
		movies = db.media.by_mediatype(Knots::ITEM_TYPE_VIDEO)
		movies.each do | movie |
			movieid = collection.fetch_movie_info(movie.name)
			if movieid && movieid.size > 0
				info = collection.fetch_movie_info(nil, movieid.values.first)
				if info && info.size > 0
					info.each_pair do | key, values |
						values = [values] if !values.instance_of?(Array)
						values.each do | value |
							if key && value
								if key != "short_overview" && key != "title"
									tag, tag_value = collection.add_tag(key, value)
									collection.tag(movie.id, tag_value.id)
								elsif key == "title"
									movie.name = value
								else
									movie.info = value
								end
							end
						end
					end
					movie.save
					success += 1
				end
			end
		end
		render("Done. #{success} movies updated.")
	end
	
	def search_subs
		if user.admin && params["id"]
			@item = collection.get_item(params["id"])
			if @item
				@result = collection.search_subs(@item.path)
			end
		end
	end
	
	def download_sub
		if user.admin
			params["extname"] = nil if params["extname"] == ""
			subdata, error = collection.download_sub(params["sub_id"])
			if subdata
				item = collection.get_item(params["media_id"])
				if item
					subfile = File.join(File.dirname(item.path), "#{File.basename(item.path, ".*")}#{params["extname"] || ".srt"}")
					if subfile != item.path
						begin
							File.open(subfile, 'w') {|f| f.write(subdata) }
						rescue Exception => ex
							@error = ex.message
						end
					end
				end
			else
				@error = error || "Unable to download subtitles."
			end
		end
	end
	
	def play
		@player = server.player
		@player.set_profile(params["profile"]) if params["profile"]
		if params["no_resume"]
			@player.set_resume(false)
		end
		@player.play(params["id"] ? params["id"].to_i : nil, params["playlist_id"] ? params["playlist_id"].to_i : nil, nil, nil, nil, user)
		render(html("play"))
	end
	
	def play_album
		items = collection.album_of_item(params["id"])
		@player = server.player
		@player.set_profile(params["profile"]) if params["profile"]
		@player.play(nil, nil, items, nil, nil, user)
		render(html("play"))
	end
	
	def play_artist
		items = collection.artist_of_item(params["id"])
		@player = server.player
		@player.set_profile(params["profile"]) if params["profile"]
		@player.play(nil, nil, items, nil, nil, user)
		render(html("play"))
	end
	
	def next_playlist_item
		@player = server.player(params["id"])
		@player.next_playlist_item
		render(html("playing"))
	end
	
	def play_playlist_item
		@player = server.player(params["id"])
		@player.play_playlist_item(params["index"])
		render(html("playing"))
	end
	
	def previous_playlist_item
		@player = server.player(params["id"])
		@player.previous_playlist_item
		render(html("playing"))
	end
	
	def add_from_youtube
		item = collection.add_from_youtube(params["url"], params["type"].to_i)
		if item
			@items = [item]
			render(html("videoitems"))
		else
			render("Unable to fetch.")
		end
	end
	
	def add_new_item
		if user.admin && params["type"] && params["url"] && params["name"] && params["category"]
			item = nil
			options = {:size => -1, :directory_changed => Time.now, :modified => Time.now, :category => params["category"], :name => params["name"]}
			dvb = params["url"].scan(/(dvb.{0,}:\/\/)(.*)/).flatten
			if dvb && dvb.size == 2
				params["url"] = dvb[0]
				options[:params] = dvb[1]
			end
			if params["type"].to_i == 0
				item = collection.add_video_item(params["url"], options)
			else
				item = collection.add_audio_item(params["url"], options)
			end
			if item
				@items = [item]
				render(html("videoitems"))
			else
				render("Unable to fetch.")
			end
			return
		end
		render("Unable to fetch.")
		
	end
	
	def update_playing
		if params["id"]
			@player = server.player(params["id"])
			render(html("playing"))
		else
			render("")
		end
	end
	
	def remove_playlist_item
		if user.admin
			item = db.playlist_items.by_id(params["id"]).first
			collection.reset_playlist(item.playlist_id)
			@playlist = db.playlists.by_id(item.playlist_id).first
			item.delete
			@items = db.media.sql("SELECT playlist_items.id AS pid, media.* FROM playlist_items LEFT JOIN media ON playlist_items.media_id = media.id WHERE playlist_id=#{@playlist.id} ORDER BY order_by")
			render(html("playlist"))
		end
	end
	
	def seek
		@player = server.player(params["id"])
		@player.seek(params["position"].to_f) if server.player(params["id"])
		render(html("progress"))
	end
	
	def progress
		@player = server.player(params["id"])
		render(html("progress"))
	end
	
	def stop
		server.player(params["id"]).stop if server.player(params["id"])
	end
	
	def delete(ids, params)
		if user.admin
			db.media.sql("DELETE FROM media WHERE id IN (#{ids.join(",")})")
		end
	end
	
	def mediacount
		render(collection.mediacount.to_s)
	end
	
	def stream_as_playlist
		if params["stream"]
			response['Content-Type'] = 'audio/x-scpls';
			response['Content-Disposition'] = "attachment; filename=knots_#{Time.now.strftime("%Y_%m_%d_%H_%M_%S")}.pls"
			render("[playlist]\nNumberOfEntries=1\n\nFile1=#{params["stream"]}")
		end
		render("")
	end
	
	def rescan(ids, params)
		if user.admin
			ids.each do | id |
				item = collection.get_item(id.to_i)
				case item.mediatype
					when Knots::ITEM_TYPE_VIDEO
						collection.add_video_item(item.path, {:name => item.name, :info => item.info, :mediatype => item.mediatype, :views => item.views, :rating => item.rating, :position => item.position, :category => item.category, :active => item.active}, item)
					when Knots::ITEM_TYPE_AUDIO
						collection.add_audio_item(item.path, {:name => item.name, :info => item.info, :mediatype => item.mediatype, :views => item.views, :rating => item.rating, :position => item.position, :category => item.category, :active => item.active}, item)
					when Knots::ITEM_TYPE_VDR || Knots::ITEM_TYPE_URL 
						collection.add_video_item(item.path, {:name => item.name, :duration => 0, :category => item.category, :mediatype => item.mediatype, :rating => item.rating, :size => -1, :modified => item.modified, :directory_changed => item.directory_changed}, item)
				end
			end
		end
	end
	
	def unset_tag(ids, params)
		if user.admin && params["tag_values"] && params["tag_values"].to_i > -1
			db.media_tags.sql("DELETE FROM media_tags WHERE tag_id = #{params["tag_values"]} AND media_id IN (#{ids.join(",")})")
		end
	end
	
	def check_server_accessibility
		if user.admin
			if server.players.size > 0
				begin
					data = Common.fetch("http://nakkiboso.com/knots2/dynknots.php?action=test&code=#{CGI::escape(server.settings.dynknots_key)}&port=#{server.settings.vlc_port_range_start || "19780"}").body
					if data
						if data.index("OK")
							if server.auth
								render("<p>Congratulations, your server seems to be accessible from the internet and you have authentication enabled.</p>")
							else
								render("<p><strong>Warning!</strong> Your server is accessible from the internet, but you haven't enabled authentication. You are sharing your media with the world!</p>")
							end
						else
							render("<p>Your server doesn't seem to be accessible from the internet. Check your firewall/router settings. Open/forward port 1978 and at least two other starting from #{server.settings.vlc_port_range_start || "19780"}.</p>")
						end
					else
						render("<p>Error on remote server. Please try again later.</p>")	
					end
				rescue Exception => ex
					render("<p>Error on remote server. Please try again later.</p>")
				end
			else
				render("<p>Please start a stream with the browser, click on 'Hide window' and try again.</p>")
			end
		end
	end
	
	def show_shares
		if params["remove"]
			if user.admin
				share = db.shares.by_id(params["remove"].to_i).first
				if share
					db.users.delete_user("='#{share.key}'")
					db.shares.delete_id(share.id)
				end
			end
		end
	end
	
	def share_item
		if user.admin
			data = server.dynknots_address
			if data
				password = Common.generate_password
				guest_account = db.users.new
				guest_account.user = password
				guest_account.role = 1
				guest_account.pass = Digest::MD5.hexdigest(password)
				guest_account.temporary = Time.now
				guest_account.save
				server.load_users
				server.load_auth
				data = data.split("/").collect!{|token|token = token.strip}
				share = db.shares.new
				share.playlist_id = (params["playlist"] && params["playlist"].to_i != 0 ? params["playlist"] : nil)
				collection.reset_playlist(share.playlist_id)
				share.media_id = (params["media"] && params["media"].to_i != 0 ? params["media"] : nil)
				share.key = password
				share.created = Time.now
				share.save
				@url = "http#{server.settings.webrick_ssl.to_i == 0 ? "" : "s"}://#{password}:#{password}@#{data[3]}:#{server.settings.webrick_port}/root/share?key=#{share.key}"
			end
		end
	end
	
	def share
		if params["key"]
			@stream = db.shares.sql("SELECT shares.*,playlists.name AS pname,media.name AS mname FROM shares LEFT JOIN playlists ON playlists.id = shares.playlist_id LEFT JOIN media ON media.id = shares.media_id WHERE key = '#{params["key"]}'").first
		end
	end
	
	def play_share
		if params["key"]
			stream = db.shares.by_key("='#{params["key"]}'").first
			if stream
				params["id"] = stream.media_id
				params["playlist_id"] = stream.playlist_id
				params["no_resume"] = true
				play
				return
			end
		end
		render("Error. Unable to play.")
	end
	
	def browse_main
		params["view"] = server.settings.show_images || "1" if !params["view"]
		["category", "tag", "value", "virtual"].each do | param |
			params[param] = nil if params[param] && params[param].strip == ""
		end
	end
	
	def remove_resumepoint
		if user.admin && params["id"]
			item = collection.get_item(params["id"])
			if item
				item.position = 0
				item.save
			end
		end
	end
	
	def show_virtual
		if user.admin && params["vid"]
			virtual = db.virtual_categories.by_id(params["vid"]).first
			if virtual
				params["view"] = 1
				params["search"] = ""
				items = db.media.sql("#{virtual.search}#{virtual.search.downcase.index("order by") ? "" : " #{params["order"]}"}")
				itemcount = items.size
				params["itemcount"] = itemcount
				@page = params["page"] ? params["page"].to_i : 1
				pageitems = server.settings.pageitems.to_i
				@pages = itemcount / pageitems
				@pages += 1 if itemcount % pageitems > 0
				@items = items[pageitems * (@page - 1), pageitems]
			end
		end
		render(html("browse"))
	end
	
	def update_collection
		if user.admin
			collection.update_database
			collection.scan_mythtv
			collection.scan_vdr
			collection.scan_dreambox
		end
	end
	
	def abort_scanning
		collection.abort_scanning if user.admin
	end
	
	def export_profile
		if user.admin && params["id"]
			profile = db.transcoding_profiles.by_id(params["id"])
			name = profile[0].name.downcase.scan(/[a-z0-9 ]/).join("").gsub(" ", "_")
			profile[0].name = nil
			response['Content-Type'] = 'applicaton/octet-stream';
			response['Content-Disposition'] = "attachment; filename=#{name}.ktp"
			sio = StringIO.new("", "w+")
			w = Zlib::GzipWriter.new(sio)
			w.write(profile.to_xml.to_s)
			w.close
			render(sio.string)
		end
	end
	
	def import_profile
		if user.admin && params["profile_id"]
			begin
				profile = db.transcoding_profiles.by_id(params["profile_id"]).first
				profile_data = Zlib::GzipReader.new(StringIO.new(params["userfile"])).read
				doc = Document.new(profile_data)
				doc.root.elements["//item"].each do | element |
					if element.name != "name" && element.name != "id"
						profile.fields[element.name] = element.text && element.text.strip != "" ? element.text : nil
					end
				end
				profile.save
			rescue Exception => ex
			end
		end
	end
	
	def change_view
		if params["view"]
			setting = db.settings.by_key("show_images").first || db.settings.new
			setting.name = "Show images"
			setting.key = "show_images"
			setting.value = params["view"]
			setting.save
			server.load_settings
		end
	end
	
	def reload_profile
		if params["id"]
			@profile = db.transcoding_profiles.by_id(params["id"]).first
			render(html("profile"))
		end
	end
	
	def update_database
		if user.admin
			if !params["myth"] && !params["vdr"] && !params["dreambox"] && !params["dbox2"]
				collection.update_database(params["id"])
			elsif params["myth"]
				collection.scan_mythtv
			elsif params["vdr"]
				collection.scan_vdr
			elsif params["dreambox"]
				collection.scan_dreambox
			elsif params["dbox2"]
				collection.scan_dbox2
			end
			render(html("media"))
		end
	end
	
	def grab_screenshot
		if user.admin
			spot = params["spot"] && params["spot"].split(":").size == 3 ? params["spot"] : nil
			collection.grab_screenshot_for_item(params["id"].to_i, nil, spot)
			render(media_screenshot(params["id"].to_i, params["mediatype"], nil, nil, false, true))
		end
	end
	
	def vacuum_database
		if user.admin
			collection.cleanup_database
			render(html("media"))
		end
	end
end
