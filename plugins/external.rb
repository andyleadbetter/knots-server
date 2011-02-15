class External < Plugin
	
	def init
		@cache = Hash.new
	end
	
	def html_methods
		nil
	end
	
	def browse
				
		show_untagged = false
		items, pages, page, limit = nil, 1, params["page"] || 1, params["limit"]
		if !params["category"] && !params["page"] && !params["search"] && !params["path"] && !params["virtual"]						
		  response["cache-control"] = "max-age=3600, private"
      items = collection.categories(user)
			items.push(KnotsDBRow.new(nil, nil, {"dir" => "/", "dirname" => "Browse by path", "id" => 0})) if user.role == "admin"
		elsif params["virtual"]
			items, pages = collection.search_items(nil, nil, nil, nil, params["order"] || "name", nil, nil, params["page"], CGI::unescape(params["virtual"])) if user.role == "admin"
		elsif params["search"]
			params["search"] = ";#{params["search"].downcase.gsub(" is ", "=").gsub(" and ", ",")}" if params["search"].downcase.index(" is ")
			items, pages = collection.search_items(params["search"], nil, nil, nil, params["order"] || "name", 100)  if user.role == "admin"
	elsif params["path"]	
			items, pages = collection.browse_by_path(params["path"], params["page"], params["order"])  if user.role == "admin"
		else
			
			items, pages = collection.browse_category(params["category"], params["tag"], params["value"],  params["page"] || 1, params["order"] || "id", nil, nil, server.settings.autoadvance == nil || server.settings.autoadvance.to_i != 0)
			if !params["tag"] && !params["value"]
				show_untagged = true
			end
		end
		if items
        if !params["format"] || params["format"].downcase == "xml"
        doc = items.to_xml
        elem = REXML::Element.new("pages")        
        elem.add_element("current").text = page
        elem.add_element("total").text = pages
        elem.add_element("totalitems").text = items.count
        doc.root.insert_before("/root/items",elem)
        render(doc.to_s)
      elsif params["format"] == "yaml"
        items.push(KnotsDBRow.new(nil, nil, {"page" => page, "pages" => pages}))
        render(items.to_yaml)
      end  
			items.each do | item |
				item.path = nil if !params["path"]
				if !item.dir
					item = fix_item(item) 
					show_untagged = false if item.name
				end
				if item.no_untagged
					show_untagged = false
				end
			end
			if show_untagged
				untagged = {"id" => -1, "tag" => "untagged"}
				item = KnotsDBRow.new(nil, nil, untagged)
				items.push(item)
			end	
		else
			render("")
		end
	end
	
	def browse_by_path
		if user.role == "admin"
			items = collection.browse_by_path(params["path"])
			render(items.method("to_#{params["format"] || "xml"}").call.to_s)
		end
	end
	
	def test_connection
		render("#{(server.settings.server_name || "Knots server")}/KNOTS_OK\n")
	end
	
	def play
		player = server.player
		player.set_profile(params["profile"]) if params["profile"]
		player.play(params["id"] ? params["id"].to_i : nil, params["playlist_id"] ? params["playlist_id"].to_i : nil, nil, params["audio_language"], params["subtitle_language"], user)
		render("#{player.player_id}:#{player.player_pass}END_CONTENT")
	end
	
	def clear_position
		if user.admin
			item = collection.get_item(params["id"])
			if item
				item.position = 0
				item.save
			end
		end
		render("OK")
	end
	
	def play_album
		items = collection.album_of_item(params["id"])
		if items.size > 0
			player = server.player
			player.set_profile(params["profile"]) if params["profile"]
			player.play(nil, nil, items, params["audio_language"], params["subtitle_language"], user)
			render("#{player.player_id}:#{player.player_pass}END_CONTENT")
		end
	end
	
	def play_artist
		items = collection.artist_of_item(params["id"])
		if items.size > 0
			player = server.player
			player.set_profile(params["profile"]) if params["profile"]
			player.play(nil, nil, items, params["audio_language"], params["subtitle_language"], user)
			render("#{player.player_id}:#{player.player_pass}END_CONTENT")
		end
	end
	
	def play_playlist
		player = server.player
		player.set_profile(params["profile"]) if params["profile"]
		player.play(nil, params["id"], nil, params["audio_language"], params["subtitle_language"], user)
		render("#{player.player_id}:#{player.player_pass}END_CONTENT")
	end
	
	def play_resultset
		items = db.media.sql("SELECT media.*,media_images.image_id AS mid FROM media LEFT JOIN media_images ON media_images.media_id = media.id WHERE media.id IN (#{params["ids"]})")
		if items.size > 0
			player = server.player
			player.set_profile(params["profile"]) if params["profile"]
			player.play(nil, nil, items, params["audio_language"], params["subtitle_language"], user)
			render("#{player.player_id}:#{player.player_pass}END_CONTENT")
		end
	end
	
	def share_playlist
		if user.admin
			if params["playlist"] && params["profile"]
				data = server.dynknots_address
				if data
					data = data.split("/").collect!{|token|token = token.strip}
					share = db.shares.sql("SELECT * FROM shares WHERE playlist_id=#{params["playlist"]} AND transcoding_profile=#{params["profile"]}").first
					if !share
						password = Common.generate_password
						guest_account = db.users.new
						guest_account.user = password
						guest_account.role = 1
						guest_account.pass = Digest::MD5.hexdigest(password)
						guest_account.temporary = Time.now
						guest_account.save
						server.load_users
						server.load_auth
						share = db.shares.new
						share.playlist_id = params["playlist"]
						collection.reset_playlist(playlist_id)
						share.key = password
						share.created = Time.now
						share.transcoding_profile = params["profile"]
						share.save
						render("http#{server.settings.webrick_ssl.to_i == 0 ? "" : "s"}://#{password}:#{password}@#{data[3]}:#{server.settings.webrick_port}/root/share?key=#{share.key}END_CONTENT")
					else
						render("http#{server.settings.webrick_ssl.to_i == 0 ? "" : "s"}://#{share.key}:#{share.key}@#{data[3]}:#{server.settings.webrick_port}/root/share?key=#{share.key}END_CONTENT")
					end
				end
			end
		end
	end
	
	def play_share
		if params["key"]
			stream = db.shares.by_key("='#{params["key"]}'").first
			if stream
				player = server.player
				player.set_profile(stream.transcoding_profile) if stream.transcoding_profile
				player.play(stream.media_id, stream.playlist_id, nil, params["audio_language"], params["subtitle_language"], user)
				render("#{player.player_id}:#{player.player_pass}END_CONTENT")
			end
		end
		render("Error. Unable to play.")
	end
	
	def next_playlist_item
		player = server.player(params["player_id"])
		if player
			player.next_playlist_item
			render("OK")
		else
			render("FAIL")
		end
	end
	
	def previous_playlist_item
		player = server.player(params["player_id"])
		if player
			player.previous_playlist_item
			render("OK")
		else
			render("FAIL")
		end
	end
	
	def select_playlist_item
		player = server.player(params["player_id"])
		if player
			player.play_playlist_item(params["index"])
			render("OK")
		else
			render("FAIL")
		end
	end
	
	def stop
		player = server.player(params["client_id"])
		if player
			player.stop
			render("OK")
		else
			render("FAIL")
		end
	end
	
	def seek
		if params["player_id"] && params["position"]
			player = server.player(params["player_id"])
			if player
				player.seek(params["position"].gsub(",", ".").to_f)
				render("OK")
				return
			end
		end
		render("FAIL")
	end
	
	def lyrics
		if params["id"]
			lyrics = collection.lyrics_for_item(params["id"].to_i, false)
			render("#{lyrics}END_CONTENT")
			return
		end
		render("FAIL")
	end
	
	def rate
		if user.admin && params["id"] && params["rating"]
			item = collection.get_item(params["id"])
			if item && params["rating"].to_i >= 0 && params["rating"].to_i <= 10
				item.rating = params["rating"].to_i
				item.save
			end
		end
	end
	
	def playlists
		render(db.playlists.all.method("to_#{params["format"] || "xml"}").call.to_s) if user.role == "admin"
	end
	
	def playlist
		if params["id"] && user.role == "admin"
			render(db.media.sql("SELECT playlist_items.id AS pid, media.*,media_images.image_id AS mid FROM playlist_items LEFT JOIN media ON playlist_items.media_id = media.id LEFT JOIN media_images ON media_images.media_id = media.id WHERE playlist_id=#{params["id"]} ORDER BY order_by").method("to_#{params["format"] || "xml"}").call.to_s)
		end
		render("OK")
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
			render("OK")
		end
		render("FAIL")
	end
	
	def add_results_to_playlist
		if user.admin && params["ids"] && params["playlist"]
			order_by = db.playlist_items.sql("SELECT MAX(order_by) AS order_by FROM playlist_items WHERE playlist_id=#{params["playlist"]} LIMIT 1").first
			order_by = order_by ? order_by.order_by.to_i + 1 : 1
			params["ids"].split(",").each_with_index do | id, index |
				item = db.playlist_items.new
				item.playlist_id = params["playlist"]
				collection.reset_playlist(item.playlist_id)
				item.media_id = id
				item.order_by = order_by + index
				item.save
			end
			render("OK")
		end
		render("FAIL")
	end
	
	def remove_from_playlist
		if params["pid"]
			item = db.playlist_items.by_id(params["pid"]).first
			collection.reset_playlist(item.playlist_id)
			item.delete if item
			render("OK")
		elsif params["id"] && params["playlist"]
			items = db.playlist_items.sql("SELECT * FROM playlist_items WHERE playlist_id=#{params["playlist"]} AND media_id=#{params["id"]}")
			collection.reset_playlist(params["playlist"])
			items.each do | item |
				item.delete
			end
			render("OK")
		end
		render("FAIL")
	end
	
	def shuffle_playlist
		if user.admin && params["id"]
			collection.shuffle_playlist(params["id"])
			render("OK")
		end
		render("FAIL")
	end
	
	def loop
		if params["player_id"]
			player = server.player(params["player_id"])
			if player
				player.loop(params["loop"] && params["loop"] == "true")
			end
		end
	end
	
	def player_properties
		if params["player_id"]
			player = server.player(params["player_id"])
			if player
				attributes = Hash.new	
				"seekable?,mediatype,title,position,duration,media_id,playlistindex,playlist_length,currently_playing_filename,video_width,video_height,mux,stream,port,buffer,address,looped?".split(",").each do | key |
					begin
						val = player.method(key).call
						if val.instance_of?(Array)
							val = val.join("|")
						elsif val.instance_of?(KnotsDBRow)
							pairs = Array.new
							val.fields.each_pair do | key, value |
								pairs.push("#{key}=#{value}")
							end
							val = pairs.join(",")
						elsif !val.instance_of?(String)
							val = val.to_s
						end
						attributes[key.gsub("?", "")] = val
					rescue Exception => ex
						render(@cache[params["player_id"]])
						return
					end
				end
				before = attributes["seekable"]
				attributes["seekable"] = "false" if Common.remote_file(attributes["currently_playing_filename"])
				arr = KnotsArray.new
				arr.push(KnotsDBRow.new(nil, nil, attributes))
				xml  = arr.to_xml.to_s
				@cache[params["player_id"]] = xml
				render(xml)
			end
		end
	end
	
	def currently_playing_playlist
		if params["player_id"]
			player = server.player(params["player_id"])
			if player
				playlist = player.playlist.to_xml
				render("#{playlist}END_CONTENT")
			end
		end
		render("FAIL")
	end
	
	def fix_item(item)
		begin
			item.name = Iconv.conv("utf-8", "utf-8", item.name) if item.name 
		rescue Exception => ex
			item.name = "Unknown"
		end
		begin
			item.info = Iconv.conv("utf-8", "utf-8", item.info) if item.info
		rescue Exception => ex
			item.info = ""
		end
		begin
			item.value = Iconv.conv("utf-8", "utf-8", item.value.strip) 
			
		rescue Exception => ex
			item.value = "Unknown"
		end
		begin
			item.duration = Common.position_for_ffmpeg(item.duration) if item.duration
		rescue Exception => ex
			item.duration = "Unknown"
		end
		begin
			item.position = Common.position_for_ffmpeg(item.position) if item.position
		rescue Exception => ex
			item.position = "Unknown"
		end
		item.added = item.added.strftime("%Y-%m-%d") if item.added
		item.modified = item.modified.strftime("%Y-%m-%d") if item.modified
		return item
	end
	
	def info
		item = collection.get_item(params["id"])
		if item.mediatype == Knots::ITEM_TYPE_VDR
			begin
				info = "<small>"
				vdr = server.plugins["vdr"]
				if vdr.enabled
					epg = vdr.epg
					epg.size.times do | i |
						epg_data = epg[i + 1]
						if epg_data && epg_data[0][item.name]
							programs = vdr.programs_for_date(item.name, Time.now.strftime("%Y-%m-%d"), epg_data)
							programs.each do | program |
								begin
								program = "<b><big>#{program[2].strip}</big></b>\n#{program[0].strftime("%H:%M")} - #{program[1].strftime("%H:%M")}\n\n<i>#{program[3] ? "#{program[3]}\n" : ""}</i>".strip
									info += "#{program}\n\n"
								rescue Exception => ex
								end
							end
						end
					end
					info = "#{info.strip}</small>"
					item.info = info
				end
			rescue Exception => ex
			end
		end
		str = "<b>#{entity_escape(item.name)}</b>\n\n"
		str += "#{entity_escape(item.info)}\n\n" if item.info && item.info.strip != ""
		["duration", "views", "rating", "aspect"].each do | key |
			value = item.fields[key]
			if value
				key = "playcount" if key == "views" && item.mediatype == Knots::ITEM_TYPE_AUDIO
				value = "Unknown" if key == "duration" && value.to_i <= 0
				value = Common.position_for_ffmpeg(item.duration) if key == "duration"
				if key != "duration" || item.fields["position"] == 0
					str +="<b>#{key.capitalize}</b>\n  #{entity_escape(value.to_s)}\n"
				else
					str +="<b>Resume position</b>\n  #{Common.position_for_ffmpeg(item.position * item.duration)} / #{value}\n"
				end
			end
		end
		tags = collection.tags_for_item(params["id"])
		tags.each_pair do | key, value |
			str +="<b>#{entity_escape(key.beautify)}#{value.size > 1 ? "s" : ""}</b>\n  #{entity_escape(value.sort.join("\n  "))}\n"
		end
		render("#{str}END_CONTENT")
	end
	
	def refetch_screenshot
		if params["id"] && user.admin
			collection.grab_screenshot_for_item(params["id"],nil, nil, nil)
			img = db.media_images.by_media_id(params["id"]).first
			if img
				render("#{img.image_id}END_CONTENT")
			end
		end
	end
	
	def entity_escape(str)
		if str
			str = str.gsub(/&(?!(?:[a-zA-Z][a-zA-Z0-9]*|#\d+);)(?!(?>(?:(?!<!\[CDATA\[|\]\]>).)*)\]\]>)/m, '&amp;')
		end
		str
	end
	
	def transcoding_profiles
		render(db.transcoding_profiles.all.method("to_#{params["format"] || "xml"}").call.to_s)
	end
	
	def swap_playlist_items
		if user.admin && params["pid"] && params["with"]
			item0 = db.playlist_items.by_id(params["pid"]).first
			if item0
				nitems = db.playlist_items.sql("SELECT * FROM playlist_items WHERE playlist_id=#{item0.playlist_id} AND order_by IS NULL")
				if nitems.size > 0
					items = db.playlist_items.by_playlist_id(item0.playlist_id)
					items.each do | item |
						item.order_by = item.id
						item.save
					end
					item0 = db.playlist_items.by_id(params["pid"]).first
				end
				item1 = db.playlist_items.by_id(params["with"]).first
				if item0 && item1
					order_by = item0.order_by
					item0.order_by = item1.order_by
					item1.order_by = order_by
					item0.save
					item1.save
					collection.reset_playlist(item0.playlist_id)
					render("OK")
					return
				end
			end
		end
		render("FAIL")
	end
	
	def new_playlist
		if user.admin && params["name"]
			playlist = db.playlists.new
			playlist.name = params["name"]
			playlist.save
			render("#{playlist.id}END_CONTENT")
		end
	end
	
	def delete_playlist
		if params["id"]
			db.playlists.delete_id(params["id"]) if params["id"].to_i != 1
			collection.reset_playlist(params["id"])
			db.playlist_items.delete_playlist_id(params["id"])
			render("OKEND_CONTENT")
		end
	end
	
	def all_tags
		tags = collection.all_tags
		render(tags.method("to_#{params["format"] || "xml"}").call.to_s)
	end
	
	def subtitles
		if params["id"] && user.role == "admin"
			data = collection.search_subs(nil, collection.get_item(params["id"]))
			if data
				subs = KnotsArray.new
				data.each do | result | 
					subs.push(KnotsDBRow.new(nil, nil, {"id" => result["IDSubtitleFile"], "ext" => File.extname(result["SubFileName"]).gsub(".", ""), "name" => "#{result["LanguageName"]} #{result["SubFileName"]}"}))
				end
				xml = subs.method("to_#{params["format"] || "xml"}").call.to_s
				render(xml)
			end
		end
	end
	
	def root_paths
		if user.admin
			paths = db.scanned.all
			paths.each do | path |
				path.path = File.basename(path.path)
			end
			render(paths.method("to_#{params["format"] || "xml"}").call.to_s)
		end
	end
	
	def update_collection
		if user.admin && params["id"]
			if params["id"].to_i == 0
				collection.update_database
				collection.scan_mythtv
				collection.scan_vdr
			else
				collection.update_database(params["id"])
			end
		end
	end
	
	def download_sub
		if params["id"] && params["subid"] && params["ext"] && user.role == "admin"
			subdata = collection.download_sub(params["subid"])
			item = collection.get_item(params["id"])
			if item
				subfile = File.join(File.dirname(item.path), "#{File.basename(item.path, ".*")}.#{params["ext"]}")
				if subfile != item.path
					begin
						File.open(subfile, 'w') {|f| f.write(subdata) }
						render("OK")
						return
					rescue Exception => ex
						@error = ex.message
					end
				end
			end
		end
		render("FAIL")
	end
	
	def all_values_for_tag
		if params["id"]
			tags = collection.all_values_for_tag(params["id"])
			render(tags.method("to_#{params["format"] || "xml"}").call.to_s)
		end
	end
	
	def tags
		if params["id"]
			tags = collection.tags_for_item(params["id"])
			render(tags.method("to_#{params["format"] || "xml"}").call.to_s)
		else
			render("")
		end
	end
	
	def download
		if user.admin && params["id"]
			item = db.media.by_id(params["id"]).first
			if item && File.readable?(item.path) && File.size(item.path) < (server.settings.filesize_limit ? server.settings.filesize_limit.to_i : 10000000)
				response['Content-Length'] = File.size(item.path)
				response["Content-Type"] = "application/octet-stream"
				response['Content-Disposition'] = "attachment; filename=#{File.basename(item.path)}"
				data = File.open(item.path, "r") {|f| f.read}
				render(data)				
			else
				render("FAIL")
			end
		end
	end
	
	def tag_item
		if params["id"] && params["tag"] && params["value"] && user.role == "admin"
			tags = collection.add_tag(params["tag"], params["value"])
			params["id"].split(",").each do | id |
				collection.tag(id, tags[1].id)
			end
			begin
				if params["tag"] == "album" || params["tag"] == "artist"
					artist = db.media_tags.sql("SELECT tag_values.* FROM tags,tag_values,media_tags WHERE tags.tag LIKE 'artist' AND tag_values.tag_id = tags.id AND tag_values.id = media_tags.tag_id AND media_tags.media_id = #{params["id"].split(",").first}").first
					album = db.media_tags.sql("SELECT tag_values.* FROM tags,tag_values,media_tags WHERE tags.tag LIKE 'album' AND tag_values.tag_id = tags.id AND tag_values.id = media_tags.tag_id AND media_tags.media_id = #{params["id"].split(",").first}").first
					if artist && album
						image = db.images.sql("SELECT images.* FROM images,media_images WHERE media_images.value_id=#{album.id} AND media_images.image_id = images.id").first
						if image
							collection.add_image_to_album(artist, album, image)
							render("OK_ALBUM")
						end
					end
				end
			rescue Exception => ex
			end
			render("OK")
		else
			render("FAIL")
		end
	end
end
