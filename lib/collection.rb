require 'find'
require 'iconv'
require 'open3'
require 'rexml/document'
require 'cgi'
require 'timeout'
require 'xmlrpc/client'
require 'zlib'
require 'stringio'
include Find
include REXML

class Collection
	
	def initialize(server)
		if server
			@server = server
			server.require_3rdparty 'mp3info'
			@inotify = nil
			require 'win32/open3' if Common.windows_os? && RUBY_VERSION < "1.9"
			@server = server
			@knots_api_key = "1db8444488077b606c7039ddcd5ba67a"
			@renamed = Array.new
			start_inotify
		end
	end
	
	def ignore_file_changes?(filename)
		!(scanned_extensions.include?(File.extname(filename).gsub(".", "")) && File.basename(filename)[0,1] != ".")
	end

	
	def start_inotify
		if !@inotify
			begin
				server.require_3rdparty 'INotify'
				server.log("Inotify enabled")
				Thread.new do
					@inotify = INotify::INotify.new
					scanned_paths.each do | dir |
						Find.find(dir) do |file|
							if !File.directory?(file) && File.basename(file)[0,1] != "."
								Find.prune
							else
								break if !watch_dir(file)
							end
						end
					end
					while @inotify
						events = []
						while (events.empty? && @inotify)
							if @inotify
								events.push(*@inotify.next_events)
								events = events.delete_if { |event| ignore_file_changes?(event.filename) }
							end
						end
						handle_inotify_event(events) if @inotify
					end
				end
			rescue Exception => e
				server.log("Inotify not enabled => #{e.message}")
			end
		else
			@inotify.close
			@inotify = nil
			start_inotify
		end
	end
	
	def inotify_enabled?
		return @inotify != nil
	end
	
	def watch_dir(dir)
		if @inotify
			begin
				inotify_mask = INotify::Mask.new(INotify::IN_MODIFY.value | INotify::IN_CREATE.value | INotify::IN_DELETE.value | INotify::IN_CLOSE_WRITE.value | INotify::IN_MOVED_TO.value | INotify::IN_MOVED_FROM.value, 'filechange')
				@inotify.watch_dir(dir, inotify_mask)
				server.log("Inotify watch dir #{dir}", 2)
				return true
			rescue Exception => ex
				return !ex.message.index("No space left on device")
			end
		end
	end
	
	def handle_inotify_event(events)
		events.each do | e |
			file = File.join(e.path, e.filename)
			file = file.gsub("/", "\\") if Common.windows_os?
			server.log("Inotify event #{e.type} for #{file}", 2)
			case e.type
				when 'create'
					if File.directory?(file)
						watch_dir(file)
					end
				when 'close_write'
					item = db.media.by_path("=\"#{file}\"").first
					if !item
						if File.size(file) > 0
							if is_audio_file?(file)
								add_music_item(file)
							elsif is_video_file?(file)
								if !is_vdr_file?(filename)
									add_video_item(file)
								else
									add_vdr_item(File.dirname(File.dirname(filename)))
								end
							end
							watch_dir(File.dirname(file))
						end
					end
				when 'moved_from'
					item = db.media.by_path("=\"#{file}\"").first
					@renamed.push(item) if item
				when 'moved_to'
					item = @renamed.shift
					if item
						item.path = file
						item.save
						watch_dir(File.dirname(file))
					end
				when 'delete'
					db.media.delete_path("=\"#{file}\"")
					if scanned_paths.include?(file)
						remove_scan_path(nil, file)
					end
			end	
		end
	end
	
	def add_scan_path(path)
		path = path.gsub("/", "\\") if Common.windows_os?
		if !Common.array_part_of_string?(scanned_paths, path) && !Common.string_part_of_array?(scanned_paths, path) && File.exists?(path) && File.directory?(path) 
			scanned = db.scanned.new
			scanned.path = path
			scanned.video_category = 1
			scanned.audio_category = 2
			scanned.image_category = 3
			scanned.save
			start_inotify
			set_latest_path(path)
			server.log("Added scanned path #{path}", 2)
			return scanned
		end
		nil
	end
	
	def set_latest_path(dir)
		server.log("Saving last used dir #{dir}", 2)
		setting = server.db.settings.by_key("=\"latest_path\"").first || server.db.settings.new
		setting.key = "latest_path"
		setting.value = dir
		setting.save
		server.load_settings
	end
	
	def remove_scan_path(id = nil, path = nil)
		if id
			path = db.scanned.by_id(id).first.path
			server.log("Removing scanned path #{path}", 2)
			db.scanned.delete_id(id)
			remove_media(path)
		elsif path
			server.log("Removing scanned path #{path}", 2)
			db.scanned.delete_path(path)
			remove_media(path)
		end
		start_inotify
	end
	
	def remove_media(path)
		if path
			media = db.media.by_path("LIKE \"#{path}%\"")
			media.each do | item |
				if [Knots::ITEM_TYPE_VIDEO,Knots::ITEM_TYPE_AUDIO,Knots::ITEM_TYPE_IMAGE].include?(item.mediatype) 
					delete_item(nil, item)
				end
			end
		end
	end
	
	def scanned_paths
		db.scanned.all.combine("path")
	end
	
	def scan_path(path)
		root_path = get_root_path(path)
		@skipped = Array.new
		if File.exists?(path) && File.directory?(path) && File.readable?(path)
			server.log("Scanning root path #{path}", 2)
			find(path) do | dir |
				if scannable?(dir)
					server.log("Scanning dir #{dir}", 2)
					if !Common.is_vdr_dir?(dir) && !Common.is_dvd_dir?(dir)
						files = media_files(dir)
						files.each do | file |
							filename = File.join(dir, file)
							filename = filename.gsub("/", "\\") if Common.windows_os?
							if File.exists?(filename)
								begin
									if !is_playlist?(filename)
										item = db.media.by_path("=\"#{filename}\"").first
										if !item
											if is_video_file?(filename)
												if !is_dvd_image?(filename)
													add_video_item(filename, {:category => root_path.video_category})
												else
													add_dvd_image(filename)
												end
											elsif is_audio_file?(filename)
												add_audio_item(filename, {:category => root_path.audio_category})
											elsif is_image_file?(filename)
												add_video_item(filename, {:category => root_path.image_category, :mediatype => Knots::ITEM_TYPE_IMAGE})
											end
										end
									else
										@playlists[filename] = [root_path.video_category, root_path.audio_category]
									end
								rescue Exception => ex
									server.log("Error adding file #{filename} Error was: #{ex.message}\nBacktrace:\n\n#{ex.backtrace}", 2)
								end
							end
							return if !@scanning
						end
					elsif Common.is_vdr_dir?(dir)
						@skipped.push(dir)
						add_vdr_item(dir)
					elsif Common.is_dvd_dir?(dir)
						@skipped.push(dir)
						add_dvd_dir(dir)
					end
				end
				return if !@scanning
			end
		end
	end
	
	def add_vdr_item(dir)
		server.log("Adding vdr item #{dir}", 2)
		vdr_info = Common.vdr_info(dir, server.settings.vdr_charset)
		filename = File.join(dir, "001.vdr")
		filename = filename.gsub("/", "\\") if Common.windows_os?
		item = db.media.by_path("=\"#{filename}\"")
		if !item || item.size == 0
			options = Hash.new
			options[:duration] = 0
			options[:size] = 0
			Dir["#{dir}/*.vdr"].sort.delete_if {|x| ["info.vdr", "index.vdr", "resume.vdr"].include?(File.basename(x))}.each do | file |
				info = Common.parse_info(get_file_info(file))
				options[:duration] += info[:duration] if info
				options[:size] += File.size(file)
			end
			options[:name] = "#{vdr_info["T"]} - #{vdr_info["Date"]}"
			options[:info] = vdr_info["D"]
			add_video_item(filename, options)
		end
	end
	
	def add_dvd_dir(dir, options = Hash.new)
		dir = dir.gsub("/", "\\") if Common.windows_os?
		server.log("Adding dvd dir #{dir}", 2)
		item = db.media.by_path("=\"#{dir}\"")
		if !item || item.size == 0
			vob = File.join(dir, "VIDEO_TS", "VTS_01_1.VOB")
			vob = vob.gsub("/", "\\") if Common.windows_os?
			if File.exists?(vob)
				options[:name] = File.basename(dir) if !options[:name]
				parse_dvd_info(dir, options)
				add_video_item(dir, options)
			end
		end
	end
	
	def add_dvd_image(file)
		options = Hash.new
		server.log("Adding dvd image #{file}", 2)
		options[:name] = File.basename(file, ".*")
		parse_dvd_info(file, options)
		add_video_item(file, options)
	end
	
	def parse_dvd_info(file, options)
		if server.settings.lsdvd && File.exists?(file)
			cmd = "#{server.settings.lsdvd} -asvOr \"#{file}\""
			if !Common.windows_os?
				cmd += " 2> /dev/null"
			end
			data = Common.get_output(cmd)
			if data && data.strip != ""
				begin
					info = nil
					eval("info = #{data}")
					if info && info[:track]
						movietrack = info[:track][info[:longest_track] - 1]
						options[:name] = info[:title] if info[:title] && info[:title].downcase.strip != "unknown" && info[:title].strip != "" 
						options[:duration] = movietrack[:length] ? movietrack[:length].to_i : nil
						options[:width] = movietrack[:width].to_i
						options[:height] = movietrack[:height].to_i
						options[:aspect] = movietrack[:aspect] ? movietrack[:aspect].gsub("/", ":") : nil
						options[:audio_format] = movietrack[:audio] && movietrack[:audio][0] ? "#{movietrack[:audio][0][:format]},#{movietrack[:audio][0][:frequency] ? "#{movietrack[:audio][0][:frequency]} khz," : ""}#{movietrack[:audio][0][:channels] ? "#{movietrack[:audio][0][:channels].to_s} channels," : ""}#{movietrack[:audio][0][:language] ? "#{movietrack[:audio][0][:language]} language" : ""}" : nil
						options[:video_format] = "DVD,#{movietrack[:format]},#{movietrack[:fps] ? "#{movietrack[:fps].to_s} fps" : ""}".strip
						options[:tracks] = info[:track].length
					end
				rescue Exception => ex
					server.log("Error parsing dvd: #{ex.message}\n#{ex.backtrace.join("\n")}", 2)
				end
			end
		end
	end
	
	def is_dvd_image?(filename)
		return [".iso", ".img"].include?(File.extname(filename).downcase)
	end
	
	def add_video_item(filename, options = Hash.new, mediaitem = nil)
		return if options[:category] && options[:category].to_i == -1
		server.log("Adding video item #{filename} with options\n#{Common.humanize_hash(options)}", 2)
		if !options[:category]
			root_path = get_root_path(filename)
			options[:category] = root_path.video_category if root_path
		end
		info = Common.parse_info(get_file_info(filename)) || Hash.new
		item = mediaitem || db.media.new
		item.path = filename
		if Common.windows_os? && File.exists?(filename)
			item.path = filename.gsub("/", "\\")
		end
		item.name = options[:name] || Common.cleanup_filename(item.path)
		item.size = options[:size] || File.size(item.path)
		item.duration = options[:duration] || info[:duration]
		item.added = Common.time_to_datetime(Time.now)
		item.modified = options[:modified] || (Common.time_to_datetime(File.mtime(item.path)) if File.exists?(item.path))
		item.directory_changed = options[:directory_changed] || Common.time_to_datetime(File.ctime(item.path))
		item.views = options[:views] || 0
		item.position = options[:position] || 0
		item.rating = options[:rating] || 0
		item.info = options[:info]
		item.category = options[:category] || 1
		item.active = options[:active] || 1
		item.video_format = info[:video_format]
		item.audio_format = info[:audio_format]
		item.audio_bitrate = info[:audio_bitrate]
		item.width = options[:width] || info[:width]
		item.height = options[:height] || info[:height]
		item.aspect = options[:aspect] || info[:aspect]
		item.mediatype = options[:mediatype] || Knots::ITEM_TYPE_VIDEO
		item.params = options[:params]
		item.dreambox_url = options[:dreambox_url]
		item.tracks = options[:tracks]
		item.save
		grab_screenshot_for_item(item.id)
		tag_scan(nil, item) if item.mediatype == Knots::ITEM_TYPE_VIDEO
		item
	end
	
	def add_audio_item(filename, options = Hash.new, mediaitem = nil)
		return if options[:category] && options[:category].to_i == -1
		server.log("Adding audio item #{filename} with options\n#{Common.humanize_hash(options)}", 2)
		if !options[:category]
			root_path = get_root_path(filename)
			options[:category] = root_path.audio_category if root_path
		end
		info = Common.parse_info(get_file_info(filename)) || Hash.new
		item = mediaitem || db.media.new
		item.path = filename
		if Common.windows_os? && File.exists?(filename)
			item.path = filename.gsub("/", "\\")
		end
		item.name = options[:name] || Common.cleanup_filename(item.path)
		item.size = options[:size] || File.size(item.path)
		item.duration = options[:duration] || info[:duration]
		item.added = Common.time_to_datetime(Time.now)
		item.modified = options[:modified] || Common.time_to_datetime(File.mtime(item.path))
		item.directory_changed = options[:directory_changed] || Common.time_to_datetime(File.ctime(item.path))
		item.views = 0
		item.position = 0
		item.rating = 0
		item.info = options[:info]
		item.category = 2
		item.active = 1
		item.audio_format = info[:audio_format]
		item.audio_bitrate = info[:audio_bitrate]
		item.mediatype = Knots::ITEM_TYPE_AUDIO
		begin
			item.save
			grab_screenshot_for_item(item.id)
			if server.settings.dirname_tagging.to_i == 1
				tags = add_tag("artist", File.basename(File.dirname(File.dirname(filename))))
				tag(item.id, tags[1].id)
				tags = add_tag("album", File.basename(File.dirname(filename)))
				tag(item.id, tags[1].id)
			else
				Mp3Info.open(filename, :encoding => 'utf-8') do |mp3|
					mp3.tag.each_pair do | key, value |
						value = zerofy(value) if key == "tracknum"
						key = "genre" if key.index("genre")
						if key != "title"
							if !key.index("comment")
								tags = add_tag(key, value)
								tag(item.id, tags[1].id)
							end
						else
							item.name = value
							item.save
						end
					end
				end
			end
		rescue Exception => e
			#puts e.message
		end
		item
	end
	
	def get_item(media_id)
		db.media.by_id(media_id).first
	end
	
	def tags_for_item(media_id)
		mediatags = OrderHash.new
		tags = db.tags.sql("SELECT tags.tag, tag_values.value FROM tags,tag_values,media_tags WHERE media_tags.media_id=#{media_id} AND media_tags.tag_id = tag_values.id AND tag_values.tag_id = tags.id")
		tags.each do | tag |
			mediatags[tag.tag] = Array.new if !mediatags[tag.tag]
			mediatags[tag.tag].push(tag.value)
		end
		mediatags
	end
	
	def add_from_youtube(url, mediatype = Knots::ITEM_TYPE_VIDEO)
		server.log("Adding item from Youtube: #{url} type #{mediatype}", 2)
		youtube = "http://www.youtube.com/"
		url =~ /watch\?v=(.*)b/ 
		video_id = $1
		video_id = video_id.split("&")[0]
		flv_url = nil
		Common.fetch("#{youtube}watch\?v=#{video_id}").body.split("\n").each do | line |
			if line =~ /watch_fullscreen\?(.*?)video_id=([\w-]+)&(.*?)&t=([\w\%\&=-]+)&/
				flv_url = "#{youtube}get_video?video_id=#{$2}&t=#{$4};auto"
				break
			end
		end
		if flv_url
			server.log("Youtube FLV URL is #{flv_url}", 2)
			filename = mediatype == Knots::ITEM_TYPE_VIDEO ? File.join(server.settings.upload_path, "Youtube-#{video_id}.flv") : File.join(server.settings.tmpdir, "yt#{Time.now.to_f}.flv")
			user_agent = "Mozilla/5.0 (Macintosh; U; Intel Mac OS X; en-US; rv:1.8.1.11) Gecko/20071231 Firefox/2.0.0.11 Flock/1.0.5"
			system("#{server.settings.curl} -o \"#{filename}\" -L -A \"#{user_agent}\" \"#{flv_url}\"")
			if File.exists?(filename)
				if mediatype == Knots::ITEM_TYPE_AUDIO
					target = File.join(server.settings.upload_path, "Youtube-#{video_id}.mp3")
					system("#{server.settings.ffmpeg} -i #{filename} -acodec copy #{target}")
					FileUtils.rm(filename) if File.exists?(filename)
					add_scan_path(File.dirname(target))
					return add_audio_item(target) if File.exists?(target)
				else
					add_scan_path(File.dirname(filename))
					return add_video_item(filename)
				end
			end
		else
			server.log("Unable to resolve FLV URL", 2)
		end
		nil
	end
	
	def album_of_item(media_id)
		album = db.tag_values.sql("SELECT tag_values.* FROM tags,tag_values,media_tags WHERE media_tags.media_id=#{media_id} AND media_tags.tag_id = tag_values.id AND tag_values.tag_id = tags.id AND tags.tag LIKE 'album'").first
		artist = db.tag_values.sql("SELECT tag_values.* FROM tags,tag_values,media_tags WHERE media_tags.media_id=#{media_id} AND media_tags.tag_id = tag_values.id AND tag_values.tag_id = tags.id AND tags.tag LIKE 'artist'").first
		if album && artist
			return db.media.sql("SELECT DISTINCT media.*,media_images.image_id AS mid FROM media,media_tags,tags LEFT JOIN media_images ON media_images.media_id = media.id LEFT JOIN tag_values ON media_tags.media_id = #{media_id} AND media_tags.tag_id = tag_values.id AND tag_values.tag_id = tags.id AND tags.tag = 'tracknum' WHERE media_tags.tag_id = #{album.id} AND media.id IN (SELECT DISTINCT media_tags.media_id FROM media_tags WHERE media_tags.tag_id = #{artist.id}) AND media_tags.media_id = media.id GROUP BY media.id ORDER BY tag_values.value")
		end
		return db.media.by_id(media_id)
	end
	
	def artist_of_item(media_id)
		artist = db.tag_values.sql("SELECT tag_values.* FROM tags,tag_values,media_tags WHERE media_tags.media_id=#{media_id} AND media_tags.tag_id = tag_values.id AND tag_values.tag_id = tags.id AND tags.tag LIKE 'artist'").first
		if artist
			return db.media.sql("SELECT DISTINCT media.*,media_images.image_id AS mid FROM media,media_tags,tags LEFT JOIN media_images ON media_images.media_id = media.id LEFT JOIN tag_values ON media_tags.media_id = #{media_id} AND media_tags.tag_id = tag_values.id AND tag_values.tag_id = tags.id AND tags.tag = 'tracknum' WHERE media_tags.tag_id = #{artist.id} AND media_tags.media_id = media.id GROUP BY media.id ORDER BY tag_values.value")
		end
		return db.media.by_id(media_id)
	end
	
	def lyrics_for_item(media_id, formatted = true)
		item = get_item(media_id)
		tags = tags_for_item(item.id)
		if item
			if !item.lyrics || item.lyrics.empty?
				begin
					data = Common.fetch("http://search.lyrics.astraweb.com/?word=#{CGI::escape("#{item.name} #{tags.artist}")}").body
					server.log("Fetching lyrics, song: #{item.name}, artist: #{tags.artist}", 2)
					if data && !data.index("No songs in our database")
						hits = data.scan(/\d{0,}. <b><a href="(.*)">.*<\/a><\/b>/i)
						if hits.first
							data = Common.fetch("http://lyrics.astraweb.com#{hits.first.to_s}").body
							if data
								lyrics = data.scan(/<font face=arial size=2>(.*?)<\/font>/m).first
								if lyrics && lyrics.to_s.strip != ""
									if formatted
										data = "<h3>#{tags.artist} - #{item.name} - #{tags.album}</h3>#{lyrics.to_s}"
									else
										data = lyrics.to_s.gsub("<br>", "\n").gsub(/<(.|\n)*?>/, "").gsub("\n\n", "\n").strip
									end
									item.lyrics = data
									item.save
									begin
										return Iconv.con("utf-8", "iso-88591-1", data)
									rescue Exception => e
										return data
									end
								end
							end
						end
					end
				rescue Exception => ex
					server.log("Fetching lyrics failed: #{ex.message}", 2)
					return nil
				end
			else
				server.log("Using stored lyrics for #{item.name}", 2)
				return item.lyrics
			end
		end
		return nil
	end
	
	def update_item(media_id, options)
		server.log("Updating item: #{Common.humanize_hash(options)}", 2)
		item = get_item(media_id)
		if item
			fields = item.fields
			options.each_pair do | key, value |
				fields[key] = value if fields.has_key?(key)
			end
			item.save
		end
		item
	end
	
	def rate_item(media_id, rating)
		item = get_item(media_id)
		if item
			item.rating = rating
			item.save
		end
		item
	end
	
	def delete_item(item_id = nil, item = nil)
		file = item || db.media.by_id(item_id).first
		if file
			server.log("Removing #{file.path}, id: #{file.id} from collection", 2)
			media_image = db.media_images.by_media_id(file.id).first
			if media_image
				images = db.media_images.by_image_id(media_image.media_id)
				if images.size == 1
					# delete if only one file is using the image
					db.images.delete_id(images.first.id)	
				end
				media_image.delete
			end
			db.media_tags.delete_media_id(file.id)
			db.playlist_items.delete_media_id(file.id)
			file.delete
		end
	end
	
	def tag(media_id, tag_id)
		tag = db.media_tags.sql("SELECT * FROM media_tags WHERE media_id=#{media_id} AND tag_id=#{tag_id}").first
		if !tag
			tag = db.media_tags.new
			tag.tag_id = tag_id
			tag.media_id = media_id
			tag.save
		end
		return tag
	end
	
	def tag_scan(media_id, mediaitem = nil)
		item = mediaitem || get_item(media_id)
		serie_info = item.name.scan(/s(\d.?)e(\d.?)/i).flatten
		if !serie_info || serie_info.size != 2
			serie_info = item.name.scan(/(\d*)x(\d*)/i).flatten.delete_if{|x| !x || x.strip == ""}.uniq!
		end
		if serie_info && serie_info.size == 2
			serie_info = serie_info.collect!{|x| x = zerofy(x)}
			["season", "episode"].each_with_index do | tag_name, i |
				tag_value = add_tag(tag_name, serie_info[i].to_s)
				media_tag = db.media_tags.new
				media_tag.media_id = item.id
				media_tag.tag_id = tag_value[1].id
				media_tag.save
			end
		end
	end
	
	def add_category(name)
		category = db.categories.by_category("LIKE \"#{name}\"").first
		if !category
			category = db.categories.new
			category.category = name
			category.save
		end
		return category
	end
	
	def add_tag(tag_name, value = nil)
		tag = db.tags.by_tag("LIKE \"#{tag_name}\"").first
		if !tag
			tag = db.tags.new
			tag.tag = tag_name
			tag.save
		end
		if value
			tag_value = db.tag_values.sql("SELECT * FROM tag_values WHERE tag_id=#{tag.id} AND value LIKE \"#{value}\"").first
			if !tag_value
				tag_value = db.tag_values.new
				tag_value.tag_id = tag.id
				tag_value.value = value
				tag_value.save
			end
			[tag, tag_value]
		else
			tag
		end
	end
	
	def abort_scanning
		server.log("Scanning aborted", 2)
		@scanning = nil
	end
	
	def update_database(id = nil)
		@scanning = true
		scanned = !id ? scanned_paths : [db.scanned.by_id(id).first.path]
		media = !id ? db.media.all : db.media.by_path("LIKE \"#{scanned.first}%\"")
		media.each do | item |
			if [Knots::ITEM_TYPE_VIDEO,Knots::ITEM_TYPE_AUDIO,Knots::ITEM_TYPE_IMAGE].include?(item.mediatype) && (!item.path || !Common.remote_file(item.path))
				if !Common.array_part_of_string?(scanned, item.path) || !File.exists?(item.path)
					delete_item(nil, item)
					server.log("Deleting #{item.path} from collection", 2)
				end
			end
			return if !@scanning
		end
		@playlists = Hash.new
		scanned.each do | path |
			scan_path(path)
			return if !@scanning
		end
		import_playlists
	end
	
	def import_playlists
		@playlists.each_pair do | playlist, categories |
			begin
				import_playlist(playlist, nil, File.basename(playlist, ".*"), categories[0], categories[1])
			rescue Exception => ex
				server.log("Error importing #{playlist}: #{ex.message}", 2)
			end
		end
		@playlists.clear
	end
	
	def shuffle_playlist(playlist_id)
		items = db.playlist_items.sql("SELECT * FROM playlist_items WHERE playlist_id=#{playlist_id} ORDER BY RANDOM()")
		items.each_with_index do | item, i|
			item.order_by = i + 1
			item.save
		end
		reset_playlist(playlist_id)
	end
	
	def get_root_path(path)
		db.scanned.all.each do | scanned |
			return scanned if path.index(scanned.path)
		end
		nil
	end
	
	def delete_image(id)
		image = db.images.by_id(id).first
		if image
			ids = db.media_images.by_image_id(id)
			if ids.size < 2
				db.images.delete_id(id)
				db.media_images.delete_image_id(id)
			end
		end
	end
	
	def scan_vdr
		@scanning = true
		i = 1
		while (vdr = db.settings.by_key("=\"vdr#{i}\"").first)
			tokens = vdr.value.split(",")
			scan_vdr_channels(tokens[0], tokens[1].to_i, tokens[2].to_i, tokens[3], i)
			return if !@scanning
			i += 1
		end
	end
	
	def scan_mythtv
		@scanning = true
		i = 1
		while (vdr = db.settings.by_key("=\"mythtv#{i}\"").first)
			tokens = vdr.value.split(",")
			scan_mythtv_recordings(tokens[0], tokens[1], tokens[2], tokens[3], tokens[3], i)
			return if !@scanning
			i += 1
		end
	end
	
	def scan_dreambox
		@scanning = true
		i = 1
		while (dreambox = db.settings.by_key("=\"dreambox#{i}\"").first)
			tokens = dreambox.value.split(",")
			scan_dreambox_channels(tokens[0], tokens[1], tokens[2], tokens[3], tokens[4], i, tokens[5] || "1", (tokens[6] == nil || tokens[6].to_i == 1))
			return if !@scanning
			i += 1
		end
	end
	
	def scan_dbox2
		@scanning = true
		i = 1
		while (dbox2 = db.settings.by_key("=\"dbox2_#{i}\"").first)
			tokens = dbox2.value.split(",")
			scan_dbox2_channels(tokens[0], tokens[1], tokens[2], tokens[3], tokens[4], i)
			return if !@scanning
			i += 1
		end
	end
	
	def scan_vdr_channels(address, svdrp_port, streamdev_port, charset = nil, vdr_index = 1)
		begin
			category = add_category("VDR#{vdr_index > 1 ? " #{vdr_index}" : ""}")
			add_category_icon(category, "vdr")	
			data = Common.get_vdr_output(server.settings.netcat, address, svdrp_port, "LSTC")
			data.each do | line |
				if line[0,3] == "250"
					line = ("250-#{line[4, line.length]}").split(":")
					channel = "http://#{address}:#{streamdev_port}/#{line[3]}-#{line[10]}-#{line[11]}-#{line[9]}.ts"
					name = line[0].scan(/\s(.*);?/).flatten.first.split(";")[0].split(",").uniq.join(",")
					begin
						name = Iconv.conv(charset, "UTF-8", name) if charset && charset.downcase != "utf-8"
					rescue Exception => ex
					end
					item = db.media.sql("SELECT * FROM media WHERE mediatype=#{Knots::ITEM_TYPE_VDR} AND name=\"#{name}\"").first
					if !item
						add_video_item(channel, {:name => name, :duration => 0, :category => category.id, :mediatype => Knots::ITEM_TYPE_VDR, :size => -1, :modified => Time.now, :directory_changed => Time.now})
					end
				end
				return if !@scanning
			end
		rescue Exception => ex
			server.log("Error fetching VDR channels: #{ex.message}\n\nBacktrace:\n\n#{ex.backtrace.join("\n")}")
		end
	end
	
	def scan_mythtv_recordings(mysql_host, mysql_user, mysql_password, mysql_database, charset, mythtv_index)
		begin
			require 'mysql'
			my = Mysql::new(mysql_host, mysql_user, mysql_password, mysql_database)
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
			category = add_category("MythTV#{mythtv_index > 1 ? " #{mythtv_index}" : ""}")
			add_category_icon(category, "mythtv")
			recordings = db.media.by_category("=#{category.id}")
			recordings.each do | recording |
				delete_item(nil, recording) if !File.exists?(recording.path)
			end
			res.each_hash do | row |
				if charset && charset != "utf-8"
					["title", "subtitle", "description", "dirname", "category"].each do | field |
						begin
							row[field] = Iconv.conv(charset, "utf-8", row[field])
						rescue Exception => ex
						end
					end
				end
				file = File.join(row["dirname"], row["basename"])
				file = file.gsub("/", "\\") if Common.windows_os?
				if File.exists?(file)
					item = db.media.by_path("=\"#{file}\"").first
					if !item
						item = add_video_item(file, {:name => row["title"], :mediatype => Knots::ITEM_TYPE_MYTHTV, :category => category.id, :info => "#{row["subtitle"]}\n#{row["starttime"]}".strip})
						if row["category"] && row["category"] != ""
							tag, value = add_tag("category", row["category"])
							tag(item.id, value.id)
						end
						tag, value = add_tag("recorded", row["starttime"])
						tag(item.id, value.id)
					end
				end
				return if !@scanning
			end
		rescue Exception => ex
			server.log("Error fetching MythTV recordings: #{ex.message}\n\nBacktrace:\n\n#{ex.backtrace.join("\n")}")
		end
	end
	
	def scan_dreambox_channels(addr, controlport, streamport, user, pass, dreambox_index, enigma = "1", tag_mode = true)
		category = nil
		if tag_mode
			category = add_category("Dreambox#{dreambox_index > 1 ? " #{dreambox_index}" : ""}")
			add_category_icon(category, "dreambox")
			db.media.sql("DELETE FROM media WHERE category=#{category.id}")
		end
		if enigma == "1"
			data = Common.fetch("http://#{user}:#{pass}@#{addr}:#{controlport}/?screenWidth=799").body
			if data
				urls = data.scan(/\"(\/\?mode.*)\">(.*)<\/a>/).delete_if{|scanned|scanned[1].downcase.index("bouquets") == nil}
				if urls.size == 1
					data = Common.fetch("http://#{user}:#{pass}@#{addr}:#{controlport}#{urls.first[0]}").body
					if data
						urls = data.scan(/\"(\/\?mode.*)\">(.*)<\/a>/)
						if urls
							urls.each do | cat |
								data2 = Common.fetch("http://#{user}:#{pass}@#{addr}:#{controlport}#{cat[0]}").body
								urls2 = data2.scan(/\"(\/\?mode.*)\">(.*)<\/a>/)
								if urls2.size > 0
									if tag_mode
										tag, value = add_tag("category", cat[1])
										urls2.each do | channel |
											options = {:mediatype => Knots::ITEM_TYPE_DREAMBOX, :size => -1, :directory_changed => Time.now, :modified => Time.now, :category => category.id, :name => channel[1], :dreambox_url => "http://#{user}:#{pass}@#{addr}:#{controlport}#{channel[0]}"}
											item = add_video_item("http://#{user}:#{pass}@#{addr}:#{streamport}/", options)
											tag(item.id, value.id)
											return if !@scanning
										end
									else
										category = add_category(cat[1])
										add_category_icon(category, "dreambox")
										db.media.sql("DELETE FROM media WHERE category=#{category.id}")
										urls2.each do | channel |
											options = {:mediatype => Knots::ITEM_TYPE_DREAMBOX, :size => -1, :directory_changed => Time.now, :modified => Time.now, :category => category.id, :name => channel[1], :dreambox_url => "http://#{user}:#{pass}@#{addr}:#{controlport}#{channel[0]}"}
											item = add_video_item("http://#{user}:#{pass}@#{addr}:#{streamport}/", options)
											return if !@scanning
										end
									end
								end
							end
						end
					end
				else
					server.log("Unable to fetch Dreambox User bouquets")	
				end
			else
				server.log("Unable to fetch Dreambox index page")
			end
		elsif enigma == "2"
			data = Common.fetch("http://#{user}:#{pass}@#{addr}:#{controlport}/web/getservices?sRef=1:7:1:0:0:0:0:0:0:0:FROM%20BOUQUET%20%22bouquets.tv%22%20ORDER%20BY%20bouquet").body
			if data
				urls = data.scan(/<e2servicereference>(.*?)<\/e2servicereference>\s*<e2servicename>(.*?)<\/e2servicename>/m)
				urls.each do | url |
					if url.size == 2
						url[0] = url[0].gsub(" ", "%20").gsub("\"", "%22")
						data = Common.fetch("http://#{user}:#{pass}@#{addr}:#{controlport}/web/getservices?sRef=#{url[0]}").body
						if data
							urls2 = data.scan(/<e2servicereference>(.*?)<\/e2servicereference>\s*<e2servicename>(.*?)<\/e2servicename>/m)
							if urls2.size > 0
								if tag_mode
									tag, value = add_tag("category", url[1])
									urls2.each do | channel |
										options = {:mediatype => Knots::ITEM_TYPE_DREAMBOX, :size => -1, :directory_changed => Time.now, :modified => Time.now, :category => category.id, :name => CGI::unescape(channel[1]), :dreambox_url => "http://#{user}:#{pass}@#{addr}:#{controlport}/web/zap?sRef=#{channel[0]}"}
										item = add_video_item("http://#{user}:#{pass}@#{addr}:#{streamport}/#{channel[0]}", options)
										tag(item.id, value.id)
										return if !@scanning
									end
								else
									category = add_category(url[1])
									add_category_icon(category, "dreambox")
									db.media.sql("DELETE FROM media WHERE category=#{category.id}")
									urls2.each do | channel |
										options = {:mediatype => Knots::ITEM_TYPE_DREAMBOX, :size => -1, :directory_changed => Time.now, :modified => Time.now, :category => category.id, :name => CGI::unescape(channel[1]), :dreambox_url => "http://#{user}:#{pass}@#{addr}:#{controlport}/web/zap?sRef=#{channel[0]}"}
										item = add_video_item("http://#{user}:#{pass}@#{addr}:#{streamport}/#{channel[0]}", options)
										return if !@scanning
									end
								end
							end
						end
						
					end
				end
			else
				server.log("Unable to fetch Dreambox index page")
			end
		end
	end
	
	def scan_dbox2_channels(addr, controlport, streamport, user, pass, dbox2_index)
		category = nil
		category = add_category("DBox2#{dbox2_index > 1 ? " #{dbox2_index}" : ""}")
		add_category_icon(category, "dbox2")
		db.media.sql("DELETE FROM media WHERE category=#{category.id}")
		data = Common.fetch("http://#{user}:#{pass}@#{addr}:#{controlport}/?screenWidth=799").body
		if data
			urls = data.scan(/\"(\/\?mode.*)\">(.*)<\/a>/).delete_if{|scanned|scanned[1].downcase.index("bouquets") == nil}
			if urls.size == 1
				data = Common.fetch("http://#{user}:#{pass}@#{addr}:#{controlport}#{urls.first[0]}").body
				if data
					urls = data.scan(/\"(\/\?mode.*)\">(.*)<\/a>/)
					if urls
						urls.each do | cat |
							data2 = Common.fetch("http://#{user}:#{pass}@#{addr}:#{controlport}#{cat[0]}").body
							urls2 = data2.scan(/\"(\/\?mode.*)\">(.*)<\/a>/)
							if urls2.size > 0
								tag, value = add_tag("category", cat[1])
								urls2.each do | channel |
									begin
										dbox2_url = "http://#{user}:#{pass}@#{addr}:#{controlport}#{channel[0]}"
										server.log("Switching DBox2 channel #{dbox2_url}", 1)
										Common.fetch(dbox2_url).body
										sleep(2)
										server.log("Fetching stream info", 1)
										xml = Common.fetch("http://#{user}:#{pass}@#{addr}:#{controlport}/xml/streaminfo").body
										doc = Document.new(xml)
										options = {:mediatype => Knots::ITEM_TYPE_DBOX2, :size => -1, :directory_changed => Time.now, :modified => Time.now, :category => category.id, :name => channel[1], :dreambox_url => dbox2_url}
										item = add_video_item("http://#{user}:#{pass}@#{addr}:#{streamport}/0,#{doc.root.elements["pmt"].text.scan(/.{4}/).first},#{doc.root.elements["vpid"].text.scan(/.{4}/).first},#{doc.root.elements["apid"].text.scan(/.{4}/).first}", options)
										tag(item.id, value.id)
									rescue Exception => ex
										server.log("Unable to add channel: #{ex.message}")
									end
									return if !@scanning
								end
							end
						end
					end
				end
			else
				server.log("Unable to fetch DBox2 User bouquets")	
			end
		else
			server.log("Unable to fetch DBox2 index page")
		end
	end
	
	def add_category_icon(category, type, image_id = nil)
		if !category.image_id
			if !image_id
				icon = File.join(server.knots_dir, "res", "all", "#{type}.png")
				if File.readable?(icon)
					data = Common.load_file(icon)
					if data
						image = db.images.new
						image.image = image.data_to_blob(data)
						image.save
						image_id = image.id
					end
				end
			end
			if image_id
				category.image_id = image_id
				category.save
			end
		end
	end
	
	def mediacount
		server.db.media.sql("SELECT count(id) AS mediacount FROM media").first.mediacount.to_i
	end
	
	def grab_screenshot_for_item(id, position = nil, spot = nil, screenshot = nil)
		persistent = screenshot ? 1 : 0
		status = 0
		if !server.settings.screenshot || server.settings.screenshot.to_i == 1 
			item = db.media.by_id(id).first
			if item
				server.log("Grabbing screenshot for #{item.path}, id: #{item.id}, mediatype: #{item.mediatype}, position: #{position}, spot: #{spot}, screenshot: #{screenshot == nil ? "no" : "yes"}", 2)
				if spot && !position
					position = Common.ffmpeg_position_to_position(spot)
				end
				if item.mediatype == Knots::ITEM_TYPE_VIDEO || item.mediatype == Knots::ITEM_TYPE_IMAGE || item.mediatype == Knots::ITEM_TYPE_MYTHTV || ([Knots::ITEM_TYPE_VDR, Knots::ITEM_TYPE_URL, Knots::ITEM_TYPE_DREAMBOX, Knots::ITEM_TYPE_DBOX2].include?(item.mediatype) && server.settings.external_screenshot.to_i == 1)
					if item.dreambox_url
						begin
							if item.mediatype == Knots::ITEM_TYPE_DREAMBOX
								server.log("Switching Dreambox channel #{item.dreambox_url}", 1)
								Common.fetch(item.dreambox_url).body
								sleep(1)
							end
						rescue Exception => ex
							server.log("Error switching Dreambox channel #{ex.message}", 1)
						end
					end
					screenshot = Common.grab_screenshot(server.settings.ffmpeg, item.path, position, item.duration, Common.new_size_keeping_aspect(item.width, item.height, nil, 140, 186, 140).join("x"), server.settings.curl, server.settings.tmpdir, server.settings.curl_timeout) if !screenshot
				elsif item.mediatype == Knots::ITEM_TYPE_AUDIO
					@artist = db.media_tags.sql("SELECT tag_values.* FROM tags,tag_values,media_tags WHERE tags.tag LIKE 'artist' AND tag_values.tag_id = tags.id AND tag_values.id = media_tags.tag_id AND media_tags.media_id = #{id}").first
					@album = db.media_tags.sql("SELECT tag_values.* FROM tags,tag_values,media_tags WHERE tags.tag LIKE 'album' AND tag_values.tag_id = tags.id AND tag_values.id = media_tags.tag_id AND media_tags.media_id = #{id}").first
					if @artist && @album
						screenshot, status = Common.fetch_cover(@artist.value, @album.value, item.path) if !screenshot
					else
						screenshot, status = Common.fetch_cover(nil, nil, item.path) if !screenshot
					end			
				end
				if screenshot
					server.log("Got screenshot", 2)
					media_image = db.media_images.by_media_id(item.id).first || db.media_images.new
					return false if media_image.persistent && media_image.persistent.to_i == 1 && persistent == 0 && (position || spot)
					image = nil
					if media_image.image_id
						image = db.images.by_id(media_image.image_id).first
					else
						image = db.images.new
					end
					image.image = image.data_to_blob(screenshot)
					image.save
					media_image.image_id = image.id
					media_image.media_id = item.id
					media_image.persistent = persistent
					media_image.save
					if item.mediatype == Knots::ITEM_TYPE_AUDIO && @artist && @album
						add_image_to_album(@artist, @album, image, item)
					end
					return true, status
				else
					server.log("Unable to grab screenshot", 2)
				end
			end
		end
		return false, status
	end
	
	def add_image_to_album(artist, album, image, applied = nil)
		items = db.media.sql("SELECT media.*,media_tags.tag_id FROM media LEFT JOIN media_tags ON media_tags.tag_id=#{artist.id} AND media_tags.media_id = media.id WHERE mediatype = #{Knots::ITEM_TYPE_AUDIO} AND media.id IN (SELECT DISTINCT media_id FROM media_tags WHERE tag_id=#{album.id})#{applied ? " AND media.id <> #{applied.id}" : ""}")
		items.each do | item |
			media_image = db.media_images.by_media_id(item.id).first || db.media_images.new
			media_image.image_id = image.id
			media_image.media_id = item.id
			media_image.save
		end
		album_image = db.media_images.by_value_id(album.id).first || db.media_images.new
		album_image.media_id = -1
		album_image.image_id = image.id
		album_image.value_id = album.id
		album_image.save
	end
	
	def cleanup_database
		tag_values = db.tag_values.sql("SELECT * FROM tag_values WHERE id NOT IN (SELECT DISTINCT tag_id FROM media_tags)")
		tag_values.each do | tag |
			tag.delete
		end
		tags = db.tags.sql("SELECT * FROM tags WHERE id NOT IN (SELECT DISTINCT tag_id FROM tag_values)")
		tags.each do | tag |
			tag.delete
		end
		images = db.images.sql("SELECT * FROM images WHERE id NOT IN (SELECT DISTINCT image_id FROM media_images) AND id NOT IN (SELECT DISTINCT image_id FROM categories) AND id NOT IN (SELECT DISTINCT image_id FROM tags) AND id NOT IN (SELECT DISTINCT image_id FROM tag_values) AND id NOT IN (SELECT DISTINCT image_id FROM virtual_categories)")
		images.each do | image |
			image.delete
		end
		db.vacuum
	end
	
	def fetch_movie_info(name = nil, id = nil)
		if name
			server.log("Fetching movie info for #{name}", 2)
			begin
				response = Common.fetch("http://api.themoviedb.org/2.0/Movie.search?title=#{CGI::escape(name)}&api_key=#{@knots_api_key}")
				server.log("Response code was #{response.code.to_i}", 2)
				if response.code.to_i == 200
					if response && response.body.index("?xml")
						@info = OrderHash.new
						doc = Document.new(response.body)
						doc.root.elements["//moviematches"].each_element do | e |
							title = e.elements["//title"]
							id = e.elements["//id"]
							if id && title
								@info[title.text] = id.text
							end
						end
						server.log("Response was #{Common.humanize_hash(@info)}", 2)
						return @info
					end
				end
			rescue Exception => e
				server.log("Unable to fetch info: #{e.message}", 2)
			end
		elsif id
			server.log("Fetching movie info for id #{id}", 2)
			begin
				response = Common.fetch("http://api.themoviedb.org/2.0/Movie.getInfo?id=#{id}&api_key=#{@knots_api_key}")
				server.log("Response code was #{response.code.to_i}", 2)
				if response.code.to_i == 200
					if response && response.body.index("?xml")
						@info = OrderHash.new
						doc = Document.new(response.body)
						["title", "type", "imdb", "url", "short_overview", "release", "budget", "revenue"].each do | tag |
							value = doc.root.elements["//moviematches/movie/#{tag}"]
							@info[tag] = "#{tag != "imdb" ? "" : "http://www.imdb.com/title/"}#{value.text}" if value
						end
						people = doc.root.elements["//moviematches/movie/people"]
						if people
							people.each_element do | e |
								key = e.attributes["job"]
								value = e.elements["name"].text
								@info[key] = Array.new if !@info.has_key?(key)
								@info[key].push(value) if !@info[key].include?(value)
							end
						end
						server.log("Response was #{Common.humanize_hash(@info)}", 2)
						return @info
					end
				end
			rescue Exception => e
				server.log("Unable to fetch info: #{e.message}", 2)
			end
		end
		nil
	end
	
	def categories(user = nil)
		if user && user.guest
			return db.categories.sql("SELECT images.id AS mid,categories.* FROM categories LEFT JOIN images ON categories.image_id = images.id WHERE categories.id IN (#{user.categories}) ORDER BY category")
		end
		items = db.categories.sql("select categories.id,categories.category,categories.image_id AS mid FROM categories ORDER BY category")
		if server.settings.random_category_images && server.settings.random_category_images.to_i == 1
			items.each do | item |
				image = db.media_images.sql("SELECT images.id FROM images,media_images,media WHERE media.category = #{item.id} AND media_images.media_id = media.id AND media_images.image_id = images.id ORDER BY RANDOM() LIMIT 1").first
				if image
					fields = item.fields
					fields["mid"] = image.id
					item.fields = fields
				end
			end
		end
		if db.virtual_categories
			db.virtual_categories.sql("SELECT virtual_categories.id,virtual_categories.virtual,virtual_categories.search,virtual_categories.image_id AS mid FROM virtual_categories ORDER BY virtual").each do | item |
				items.push(item)
			end
		end
		check_dvd(items)		
		if server.settings.dreambox1
			i = 1
			while (dreambox = db.settings.by_key("=\"dreambox#{i}\"").first)
				tokens = dreambox.value.split(",")
				if !tokens[5] || tokens[5] == "1"
					begin
						server.log("Switching Dreambox enigma1 to pda mode", 2)
						Thread.new do
							Common.fetch("http://#{tokens[3]}:#{tokens[4]}@#{tokens[0]}:#{tokens[1]}/?screenWidth=799")
						end
					rescue Exception => ex
					end
				end
				i += 1
			end
		end
		if server.settings.dbox2_1
			i = 1
			while (dbox2 = db.settings.by_key("=\"dbox2_#{i}\"").first)
				tokens = dbox2.value.split(",")
				begin
					server.log("Switching DBox2 to pda mode", 2)
					Thread.new do
						Common.fetch("http://#{tokens[3]}:#{tokens[4]}@#{tokens[0]}:#{tokens[1]}/?screenWidth=799")
					end
				rescue Exception => ex
				end
				i += 1
			end
		end
		return items
	end
	
	def check_dvd(items)
		dvd = server.settings.dvd_drive
		name = nil
		if dvd && dvd.strip != ""
			found_dvd = false
			dvd_dir = nil
			if !Common.windows_os?
				if File.readable?(dvd) && File.exists?(dvd)
					Dir.entries(dvd).each do | dirname |
						dir = File.join(dvd, dirname)
						dir = dir.gsub("/", "\\") if Common.windows_os?
						if Common.is_dvd_dir?(dir)
							dvd_dir = dir
							break
						end
					end
				end
			else
#				require 'win32ole'
#				shell = WIN32OLE.new("Shell.Application")
#				my_computer = shell.NameSpace(17)
#				cdrom = my_computer.ParseName(server.settings.dvd_drive.gsub("/", "\\"))
				# There has to be a method for this
#				if cdrom && cdrom.Name && !cdrom.Name.index(" Drive")
#					name = cdrom.Name
#					if Common.is_dvd_dir?(dvd)
#						dvd_dir = dvd
#					end
#				end
			end
			if dvd_dir
				dvd_item = get_dvd
				name = File.basename(dvd_dir) if !name
				if !dvd_item || dvd_item.name != name
					options = Hash.new
					options[:mediatype] = Knots::ITEM_TYPE_DVD_DIR
					options[:active] = 0
					options[:name] = name
					dvd_item = add_dvd_dir(dvd_dir, options)
				end
				found_dvd = true
				items.push(dvd_item) if dvd_item
			end
			if !found_dvd
				umount_dvd
			end
		end
	end
	
	def umount_dvd
		dvd = get_dvd
		delete_item(nil, dvd) if dvd
	end
	
	def get_dvd
		 db.media.by_mediatype(Knots::ITEM_TYPE_DVD_DISC).first
	end
	
	def latest(limit = 10, user = nil)
		if user && user.guest
			return database.media.sql("SELECT * FROM media WHERE active = 1 AND (category IN (#{user.categories}) OR media.id IN (#{user.media})) ORDER BY added DESC LIMIT 10")	
		end
		return database.media.sql("SELECT * FROM media WHERE active = 1 ORDER BY added DESC LIMIT 10")
	end
	
	def search_items(search, category = nil, tag = nil, tag_value = nil, order = nil, limit = nil, offset = nil, page = nil, sql = nil, user = nil)
		results = nil
		if !sql
			search_tokens = search.split(";")
			search = search_tokens.first || ""
			query = "media.active = 1"
			if user && user.guest
				query += " AND (category IN (#{user.categories}) OR media.id IN (#{user.media}))"
			end
			from = "media"
			if category && category.to_i != -1
				query += " AND media.category=#{category}"
			end
			if tag && tag.to_i != -1
				from += ",tags,tag_values,media_tags" if !from.index("media_tags")
				query += " AND tags.id = #{tag} AND media_tags.media_id = media.id AND media_tags.tag_id = tag_values.id AND tag_values.tag_id = tags.id"
			end
			if tag_value && tag_value.to_i != -1
				query += " AND tag_values.id = #{tag_value}"
			end
			tokens = search.scan(/"([^"]+)"/).flatten.collect!{|token| token = token.strip}
			search = search.gsub("\"", "")
			tokens.each do | token |
				search = search.gsub(token, "")
			end
			tokens += search.split(" ")
			fields = ["name", "path", "info", "aspect", "width", "height", "audio_format", "audio_bitrate", "video_format"].collect!{|m| m = "media.#{m}"}
			tokens.each do | token |
				query += " AND (#{fields.join(" LIKE \"%#{token}%\" OR ")} LIKE \"%#{token}%\")"
			end
			tag_query = nil
			if search_tokens[1]
				tag_query = ""
				search_tokens = search_tokens[1].split(",")
				search_tokens.each_with_index do | search_token, index |
					search_token = search_token.split("=")
					if search_token.size == 2
						tag_query += " AND media.id IN (SELECT media.id FROM media,tags,tag_values,media_tags WHERE tags.id = tag_values.tag_id AND media_tags.tag_id = tag_values.id AND media_tags.media_id = media.id AND tags.tag LIKE \"%#{search_token[0].strip.gsub("!", "")}%\" AND tag_values.value #{!search_token[0].index("!") ? "" : " NOT "}LIKE \"%#{search_token[1].strip}%\")"
					end
				end
			end
			results = db.media.sql("SELECT DISTINCT media.*,media_images.image_id AS mid FROM #{from} LEFT JOIN media_images ON media_images.media_id = media.id WHERE #{query}#{tag_query} #{order ? " ORDER BY #{order}" : ""} #{limit ? " LIMIT #{limit}" : ""} #{offset ? " OFFSET #{offset}" : ""}")
	else
			results = db.media.sql("#{sql} LIMIT #{server.settings.virtualitems || server.settings.pageitems} OFFSET 0")
			valueids = ["-1"]
			media_map = Hash.new
			results.each do | item |
				valueids.push(item.id)
			end
			if results.size > 0
				images = db.media_images.sql("SELECT media_id,image_id FROM media_images WHERE image_id IS NOT NULL AND media_id IN (#{valueids.join(",")})")
				images.each do | image |
					media_map[image.media_id.to_i] = image.image_id
				end
			end
			results.each do | result |
				result.mid = media_map[result.id]
			end
		end
		amount = results.size
		page = (page || 1).to_i
		limit = amount if !limit
		offset = (page - 1) * limit
		pages = amount / limit
		pages += 1 if amount % limit != 0
		results = results[offset, limit]
		return results, pages
	end
	
	def browse_category(category, tag = nil, value = nil, page = nil, order = nil, limit = nil, offset = nil, auto_advance = false)
		if !tag && !value
			items = tags_for_category(category)
			if items.size == 0
				items = untagged_for_category(category, order)
			elsif items.size == 1 && auto_advance
				untagged = untagged_for_category(category, order)
				if untagged.size == 0
					items = values_for_tag(items[0].id, category)
					if items.size > 0
						if items.size > 1
							items[0].fields["no_untagged"] = true
						else
							items = items_for_value(items[0].id, category, order)
							if items.size > 0
								items[0].fields["no_untagged"]
							end
						end
					end
				end
			end
		elsif tag && !value
			if tag.to_i != -1
				items = values_for_tag(tag, category)
			else
				items = untagged_for_category(category, order)
			end
		elsif tag && value
			items = items_for_value(value, category, order)
		end
		amount = items.size
		page = (page || 1).to_i
		limit = amount if !limit
		offset = (page - 1) * limit
		pages = amount / limit
		pages += 1 if amount % limit != 0
		items = items[offset, limit]
		return items, pages
		
	end
	
	def browse_by_path(path, page = nil, order = nil, limit = nil, offset = nil)
		path = path_by_id(path)
		results = KnotsArray.new
		if !path || path == "/"
			items = db.scanned.all
			items.each do | item |
				results.push(KnotsDBRow.new(nil, nil, {"dirname" => File.basename(item.path), "dir" => "#{item.id}", "id" => 0}))
			end
		else
			separator = "/"
			path = path.gsub("/", "\\") if Common.windows_os?
			used = Array.new
			files = Array.new
			valueids = ["-1"]
			media_map = Hash.new
			result = db.media.sql("
					SELECT
						media.*,
						null AS mid
					FROM
						media 
					WHERE
						media.active = 1
					AND
						path LIKE \"#{path}%\"
					ORDER BY path")
			path = path.gsub("\\", "/") if Common.windows_os?
			result.each do | item |
				item.path = item.path.gsub("\\", "/") if Common.windows_os?
				if File.dirname(item.path) == path
					files.push(item)
					valueids.push(item.id)
				end
				filepath = File.join(path, item.path.scan(/#{path}\/(.*?)\//).flatten.first.to_s)
				filepath = filepath[0..filepath.length - 2] if filepath[filepath.length - 1, 1] == separator
				if !used.include?(filepath) && filepath != path
					results.push(KnotsDBRow.new(nil, nil, {"dirname" => File.basename(filepath), "dir" => "#{item.id},#{item.path.gsub(path, "").split(separator).size - 2}", "id" => 0}))
					used.push(filepath)
				end
			end
			if files.size > 0
				images = db.media_images.sql("SELECT media_id,image_id FROM media_images WHERE image_id IS NOT NULL AND media_id IN (#{valueids.join(",")})")
				images.each do | image |
					media_map[image.media_id.to_i] = image.image_id
				end
			end
			files.each do | file |
				file.mid = media_map[file.id] 
				results.push(file)
			end
		end
		amount = results.size
		page = (page || 1).to_i
		limit = amount if !limit
		offset = (page - 1) * limit
		pages = amount / limit
		pages += 1 if amount % limit != 0
		results = results[offset, limit]
		return results, pages
	end
	
	def path_by_id(path)
		if path != "/"
			tokens = path.split(",")
			if tokens.size == 1
				path = db.scanned.by_id(path).first.path
			else
				path = db.media.by_id(tokens[0]).first.path
				tokens[1].to_i.times do | i |
					path = File.dirname(path)
				end
				if Common.windows_os?
					path = path.gsub("\\", "/")
					if path[path.length- 1,1] == "/"
						path = path[0..path.length-2]
					end
				end
				path = "/" if db.scanned.by_path("LIKE \"#{path}/%\"").size > 0
			end
		end
		return path
	end
	
	def tags_for_category(category)
		db.tags.sql("SELECT tags.id AS id,tags.tag AS tag,tags.image_id AS mid FROM media,tags,tag_values,media_tags WHERE media.active = 1 AND media.category = #{category} AND media.id = media_tags.media_id AND media_tags.tag_id = tag_values.id AND tag_values.tag_id = tags.id GROUP BY tags.id ORDER BY tags.tag")
	end
	
	def values_for_tag(tag_id, category = nil)
		values = db.tag_values.sql("
				SELECT
					DISTINCT tag_values.id,
					tag_values.value,
					null AS mid,
					tag_values.tag_id
				FROM
					tag_values,
					media_tags,
					media
				WHERE
					tag_values.tag_id=#{tag_id}
				AND
					media.category = #{category}
				AND
					tag_values.id = media_tags.tag_id
				AND
					media_tags.media_id = media.id
				ORDER BY
					value")
		valueids = ["-1"]
		media_map = Hash.new
		values.each do | value |
				valueids.push(value.id) if value.id && value.id.to_i.to_s == value.id.to_s
		end
		images = db.media_images.sql("SELECT value_id,image_id FROM media_images WHERE image_id IS NOT NULL AND value_id IN (#{valueids.join(",")})")
		images.each do | image |
			media_map[image.value_id.to_i] = image.image_id
		end
		values.each do | value |
			value.mid = media_map[value.id.to_i]
			if !value.mid && value.image_id
				value.mid = value.image_id
			end
		end
		values
	end
	
	def all_tags
		db.tags.sql("SELECT id,tag FROM tags ORDER BY tag")
	end
	
	def all_values_for_tag(tag_id)
		db.tag_values.sql("SELECT id,value FROM tag_values WHERE tag_id=#{tag_id} ORDER BY value")
	end
	
	def all_tags_for_item(item_id)
		db.tags.sql("SELECT tags.* FROM media,tags,tag_values,media_tags WHERE media.active = 1 AND media.id = media_tags.media_id AND media_tags.tag_id = tag_values.id AND tag_values.tag_id = tags.id GROUP BY tags.id ORDER BY tags.tag")
	end
	
	def items_for_value(value_id, category, order = "added")
		db.media.sql("SELECT media.*,media_images.image_id AS mid FROM media,media_tags LEFT JOIN media_images ON media_images.media_id = media.id WHERE media.active = 1 AND media_tags.tag_id=#{value_id} AND media_tags.media_id = media.id AND media.category = #{category} ORDER BY #{order}")
	end
	
	def untagged_for_category(category, order = "added")
		db.media.sql("SELECT media.*,media_images.image_id AS mid FROM media LEFT JOIN media_images ON media_images.media_id = media.id WHERE media.active = 1 AND category=#{category} AND media.id NOT IN (SELECT DISTINCT media_id FROM media_tags) ORDER BY #{order}")
	end
	
	def deactivate_item(media_id)
		item = db.media.by_id(media_id).first
		if item
			item.active = 0
			item.save
		end
	end
	
	def rename_category(category_id, new_name)
		category = db.categories.sql("SELECT * FROM categories WHERE id <> #{category_id} AND category LIKE \"#{new_name}\"").first
		if !category
			category = db.categories.by_id(category_id).first
			category.category = new_name
			category.save
		else
			current = db.categories.by_id(category_id).first
			media = db.media.by_category(current.id)
			media.each do | item |
				item.category = category.id
				item.save
			end
			db.categories.delete_id(category_id)
		end
		return category
	end
	
	def remove_category(category_id)
		if category_id.to_i > 3
			items = db.media.by_category(category_id)
			items.each do | item |
				if item.mediatype == Knots::ITEM_TYPE_AUDIO
					item.category = 2
				elsif item.mediatype == Knots::ITEM_TYPE_IMAGE
					item.category = 3
				else
					item.category = 1
				end
				item.save
			end
			paths = db.scanned.by_video_category(category_id)
			paths.each do | path |
				path.video_category = 1
				path.save
			end
			paths = db.scanned.by_audio_category(category_id)
			paths.each do | path |
				path.audio_category = 2
				path.save
			end
			paths = db.scanned.by_image_category(category_id)
			paths.each do | path |
				path.image_category = 3
				path.save
			end
			db.categories.delete_id(category_id)
		end
	end
	
	def rename_tag(tag_id, new_name)
		tag = db.tags.sql("SELECT * FROM tags WHERE id <> #{tag_id} AND tag LIKE \"#{new_name}\"").first
		if !tag
			tag = db.tags.by_id(tag_id).first
			if tag.tag != new_name
				tag.tag = new_name
				tag.save
			end
		else
			tag_values = db.tag_values.by_tag_id(tag_id)
			tag_values.each do | tag_value |

				existing = db.tag_values.sql("SELECT * FROM tag_values WHERE id <> #{tag_value.id} AND tag_id = #{tag.id} AND value LIKE \"#{tag_value.value}\"").first
				if !existing
					tag_value.tag_id = tag.id
					tag_value.save
				else
					media_tags = db.media_tags.by_tag_id(tag_value.id)
					media_tags.each do | media_tag |
						media_tag.tag_id = existing.id
						media_tag.save
					end
					db.tag_values.delete_id(tag_value.id)
				end
			end
			db.tags.delete_id(tag_id)
		end
		return tag
	end
	
	def rename_tag_value(tag_value_id, new_name)
		tag_value = db.tag_values.by_id(tag_value_id).first
		existing = db.tag_values.sql("SELECT * FROM tag_values WHERE id <> #{tag_value.id} AND tag_id = #{tag_value.tag_id} AND value LIKE \"#{new_name}\"").first
		if !existing
			tag_value.value = new_name
			tag_value.save
		else
			media_tags = db.media_tags.by_tag_id(tag_value_id)
			media_tags.each do | media_tag |
				media_tag.tag_id = existing.id
				media_tag.save
			end
			db.tag_values.delete_id(tag_value_id)
			tag_value = existing
		end
		return tag_value
	end
	
	def remove_tag_value_from_media(mediatag_id)
		db.media_tags.delete_id(mediatag_id)
	end
	
	def remove_tag(tag_id)
		db.tags.delete_id(tag_id)
		remove_tag_value(nil, tag_id)
	end
	
	def add_tag_value(tag_id, value)
		tag_value = db.tag_values.sql("SELECT * FROM tag_values WHERE tag_id=#{tag_id} AND value LIKE \"#{value.strip}\"").first
		if !tag_value
			tag_value = db.tag_values.new
			tag_value.tag_id = tag_id
			tag_value.value = value
			tag_value.save
		end
		return tag_value
	end
	
	def remove_tag_value(value_id = nil, tag_id = nil)
		if value_id
			db.tag_values.delete_id(value_id)
			db.media_tags.delete_tag_id(value_id)
		else
			items = db.tag_values.by_tag_id(tag_id)
			items.each do | item |
				db.media_tags.delete_tag_id(item.id)
			end
			db.tag_values.delete_tag_id(tag_id)
		end
	end
	
	def server
		@server
	end
	
	def database
		return server.database
	end
	
	alias :db :database
	
	def media_files(dir)
		files = Array.new
		if File.readable?(dir)
			Dir.entries(dir).each do | file |
				files.push(file) if scanned_extensions.downcase.split(",").include?(File.extname(file.downcase).gsub(".", ""))
			end
			return files.sort.delete_if {|x| ["index.vdr", "info.vdr", "resume.vdr", "marks.vdr"].include?(x)}
		else
			return files
		end
	end
	
	def is_vdr_file?(filename)
		return File.extname(filename).downcase == ".vdr" if filename
		return false
	end
	
	def is_video_file?(filename)
		server.settings.video_ext.downcase.split(",").include?(File.extname(filename.downcase).gsub(".", ""))
	end
	def is_image_file?(filename)
		server.settings.image_ext.downcase.split(",").include?(File.extname(filename.downcase).gsub(".", ""))
	end
	
	def is_audio_file?(filename)
		server.settings.audio_ext.downcase.split(",").include?(File.extname(filename.downcase).gsub(".", ""))
	end
	
	def is_external_stream?(address)
		return address != nil && address.index("://")
	end
	
	def is_playlist?(filename)
		server.settings.playlist_ext.downcase.split(",").include?(File.extname(filename.downcase).gsub(".", ""))
	end
	
	def scanned_extensions
		"#{server.settings.video_ext},#{server.settings.audio_ext},#{server.settings.image_ext},#{server.settings.playlist_ext}"
	end
	
	def get_file_info(filename)
		return "" if filename.index("mms://") || (filename.index("http://") && server.settings.external_screenshot.to_i == 0) 
		if (filename.index("http://")) && server.settings.curl
			filename = Common.grab_video_stream(filename, server.settings.curl, server.settings.tmpdir, server.settings.curl_timeout)
		end
		info = Array.new
		if server.settings.ffmpeg
			begin
				cmd = "\"#{server.settings.ffmpeg}\" -i \"#{Common.fix_filename(filename)}\""
				info = Common.get_output(cmd, "stderr", 2).scan(/Duration:(.+?),|Video:(.+?)\n|Audio:(.+?)$/i).flatten.delete_if{|x|!x}.collect{|x| x = x.strip}
			rescue Exception => ex
			end
		end
		if info.size > 0
			return "\n#{info.join("\n")}"
		else
			return ""
		end
	end

	def opensubtitles_compute_hash(filename = nil, item  = nil)
		filename = item.path if !filename && item
		if filename && File.exists?(filename)
			filesize = File.size(filename)
			hash = filesize
			chunk_size = 64 * 1024 # in bytes
			# Read 64 kbytes, divide up into 64 bits and add each
			# to hash. Do for beginning and end of file.
			File.open(filename, 'rb') do |f|    
				# Q = unsigned long long = 64 bit
				f.read(chunk_size).unpack("Q*").each do |n|
					hash = hash + n & 0xffffffffffffffff # to remain as 64 bit number
				end
				f.seek([0, filesize - chunk_size].max, IO::SEEK_SET)
				
				# And again for the end of the file
				f.read(chunk_size).unpack("Q*").each do |n|
					hash = hash + n & 0xffffffffffffffff
				end
			end
			return sprintf("%016x", hash)
		end
		nil
	end
	
	def search_subs(filename, item = nil)
		begin
			filename = item.path if item && !filename
			if filename && File.exists?(filename)
				server.log("Searching for subtitles for #{filename}", 2)
				Timeout.timeout(10) do
					client = XMLRPC::Client.new2("http://api.opensubtitles.org/xml-rpc")
					if !@opensubtoken
						result = client.call('LogIn', '', '', '', 'Knots v0.1')
						if result["status"].index("200 OK")
							@opensubtoken = result['token']
							#puts "Logged in to opensubtitles (#{result.keys.join(",")}), token is #{@opensubtoken}"
						else
							#puts "Login to opensubtitles failed."
						end
					end
					moviehash = opensubtitles_compute_hash(filename)
					result = client.call('SearchSubtitles', @opensubtoken, [{
						'sublanguageid' => '', 
						'moviehash'     => moviehash,
						'moviebytesize' => File.size(filename)
					}])
					server.log("Response: #{Common.humanize_array(result["data"])}", 2)
					return result["data"]
				end
			end
		rescue Exception => ex
			server.log("Subtitle search error: #{ex.message}", 2)
		end
		return nil
	end
	
	def import_playlist(filename = nil, data = nil, name = nil, video_category = nil, audio_category = nil)
		if filename && !data
			data = Common.load_file(filename)
		end
		if data
			items = Array.new
			checksum = Digest::MD5.hexdigest(data)
			playlist_items = Common.parse_playlist(data)
			playlist_items.each do | playlist_item |
				item = db.media.by_path("=\"#{playlist_item[0]}\"").first || db.media.by_path("LIKE \"%#{playlist_item[0]}\"").first
				if !item
					if is_external_stream?(playlist_item[0])
						item = add_video_item(playlist_item[0], {:name => playlist_item[1], :size => -1, :directory_changed => Time.now, :modified => Time.now, :category => video_category || 1})
					elsif File.exists?(playlist_item[0]) || (filename && File.exists?(File.join(File.dirname(filename), playlist_item[0])))
						add_scan_path(File.dirname(playlist_item[0]))
						if is_video_file?(playlist_item[0])
							item = add_video_item(playlist_item[0], {:name => playlist_item[1], :category => video_category || 1})
						elsif is_audio_file?(playlist_item[0])
							item = add_audio_item(playlist_item[0], {:name => playlist_item[1], :category => audio_category || 2})
						end
					end
				end
				items.push(item) if item
			end
			if items.size > 0
				playlist = filename ? (db.playlists.by_path("=\"#{filename}\"").first || db.playlists.new) : (db.playlists.by_hash("=\"#{checksum}\"").first || db.playlists.new)
				name = File.basename(filename, ".*") if !name && filename
				playlist.name = name || "Untitled #{Time.now.strftime("%Y-%m-&d-%H-%M-%S")}"
				playlist.hash = checksum
				playlist.path = filename
				playlist.save
				db.playlist_items.delete_playlist_id(playlist.id)
				items.each_with_index do | item, index |
					playlist_item = db.playlist_items.new
					playlist_item.playlist_id = playlist.id
					playlist_item.media_id = item.id
					playlist_item.order_by = index
					playlist_item.save
				end
			end
		end
	end
	
	def reset_playlist(id)
		if id
			playlist = db.playlists.by_id(id).first
			if playlist
				playlist.resume_position = nil
				playlist.resume_index = nil
				playlist.save
			end
		end
	end
	
	def download_sub(subid)
		begin
			server.log("Downloading subtitles, id: #{subid}", 2)
			Timeout.timeout(10) do
				client = XMLRPC::Client.new2("http://api.opensubtitles.org/xml-rpc")
				result = client.call('DownloadSubtitles', @opensubtoken, [subid])
				if result["data"] && result["data"].instance_of?(Array)
					if result && result["data"] && result["data"][0] && result["data"][0]["data"]
						subdata = Zlib::GzipReader.new(StringIO.new(XMLRPC::Base64.decode(result["data"][0]["data"]))).read
						return [subdata, nil]		
					end
				else
					server.log("Unable to fetch subtitles: #{result}", 2)
				end
			end
		rescue Exception => ex
			return [nil, "Unable to download subtitles: #{ex.message}"]
		end
		return [nil, "Unable to download."]
	end
	
	def logout_opensubtitles
		if @opensubtoken
			begin
				Timeout.timeout(5) do
					client = XMLRPC::Client.new2("http://api.opensubtitles.org/xml-rpc")
					result = client.call('LogOut', @opensubtoken)
					#puts "Logged out from opensubtitles, result was #{result}"
					@opensubtoken = nil
				end
			rescue Exception => ex
			end
		end
	end
	
	def scannable?(dir)
		if File.directory?(dir) && File.readable?(dir)
			@skipped.each do | path |
				return false if dir.index(path)
			end
		else
			return false
		end
		return true
	end
	
	private
	
	def zerofy(val)
		if val && val != "" && !val.to_s.index("0") && val.to_i < 10
			return "0#{val}"
		end
		return val
	end
	
end
