class Player
	
	def initialize(vlc)
		@user = nil
		@end_count = 0
		@id = Common.generate_password
		@pass = Common.generate_password
		@vlc = vlc
		@profile = vlc.server.db.transcoding_profiles.all.first
		@names = KnotsArray.new
		@resume = (vlc.server.settings.enable_resume == nil || vlc.server.settings.enable_resume.to_i == 1) 
		vlc.init(player_id)
	end
	
	def vlc
		@vlc
	end

	def player_id
		@id 
	end
	
	def player_pass
		@pass
	end
	
	def set_resume(resume)
		@resume = resume
	end
	
	def resume
		@resume
	end
	
	def set_profile(profile)
		@profile = vlc.server.db.transcoding_profiles.by_id(profile).first
	end
	
	def profile
		@profile
	end
	
	def play(id = nil, playlist_id = nil, itemlist = nil, audio_language = nil, subtitle_language = nil, user = nil)
		return if !user
		@user = user
		items = itemlist || (id ? vlc.server.db.media.by_id(id) : vlc.server.db.media.sql("SELECT media.*,media_images.image_id AS mid from playlist_items LEFT join media_images ON media_images.media_id = playlist_items.media_id LEFT JOIN media ON playlist_items.media_id = media.id WHERE playlist_id=#{playlist_id} ORDER BY order_by ASC"))
		if user.guest && items.size > 0
			allowed_items = vlc.server.db.media.sql("SELECT * FROM media WHERE category IN (#{user.categories})").collect!{|x| x = x.id.to_i}
			removed = Array.new
			items.each do | item |
				if !allowed_items.include?(item.id)
					removed.push(item)
				end
			end
			removed.each do | item |
				items.delete(item)
			end
		end
		if items.size > 0
			vlc.clear_playlist(player_id)
			if vlc.running
				vlc.set_output(player_id, load_profile(items.size == 1 ? items.first : nil))
				items.each do | item |
					if Common.remote_file(item.path) || File.exists?(item.path)
						if item.dreambox_url && items.size == 1
							begin
								vlc.server.log("Switching Dreambox channel #{item.dreambox_url}", 1)
								Common.fetch(item.dreambox_url).body
							rescue Exception => ex
								vlc.server.log("Error switching Dreambox channel #{ex.message}", 1)
							end
						end
						mid = item.mid
						item.fields.delete("mid") # Prevent save error because of extra field
						item.views += 1
						item.position = 0 if items.size > 1
						item.save
						item.fields["mid"] = mid
						@names.push(item)
						vlc.add_to_playlist(player_id, item.path)
						load_params(item.params)
					end
				end
				if @names.size > 0
					vlc.set_option(player_id, "audio-language", audio_language || vlc.server.settings.audio_language || "en,any")
					if vlc.server.settings.subtitles && vlc.server.settings.subtitles.to_i == 1
						vlc.set_option(player_id, "sub-language", subtitle_language || vlc.server.settings.subtitle_language || "")
					end
					vlc.play(player_id)
					(vlc.server.settings.playback_wait || 10).to_i.times do | i |
						if vlc.playback_started?(player_id)
							vlc.server.log("Starting stream at http://#{vlc.server.auth ? "#{player_id}:#{player_pass}@" : ""}localhost:#{port}/#{stream}")
							if !playlist_id
								item = items.first
								if item.position > 0.0 && resume
									vlc.seek(player_id, item.position - 0.0005)
								end
							else
								playlist = vlc.server.db.playlists.by_id(playlist_id).first
								if playlist && playlist.resume_index
									vlc.play_playlist_item(player_id, playlist.resume_index)
								end
								if playlist && playlist.resume_position && playlist.resume_position.to_f > 0.0
									vlc.play_playlist_item(playlist.resume_index, player_id)
									vlc.seek(player_id, playlist.resume_position.to_f - 0.0005)
								end
							end
							return
						else
							sleep 1
						end
					end
				end
				vlc.stop(player_id)
			end
		end
	end
	
	def started?
		vlc.started?(player_id)
	end
	
	def playlist_length
		if !currently_playing.tracks
			return vlc.playlist(player_id).size
		else
			return currently_playing.tracks
		end
	end
	
	def loop(looped)
		vlc.loop(player_id, looped)
	end
	
	def looped?
		vlc.looped?(player_id)
	end
	
	alias :playlist_size :playlist_length
	
	def playlist
		@names
	end
	
	def playlistindex
		vlc.playlistindex(player_id)
	end
	
	def seekable?
		vlc.seekable?(player_id)
	end
	
	def play_playlist_item(index)
		vlc.play_playlist_item(player_id, index)
	end
	
	def next_playlist_item
		if !currently_playing.tracks
			vlc.next_playlist_item(player_id)
		else
			seek(0.999)
		end
	end
	
	def previous_playlist_item
		if !currently_playing.tracks
			vlc.previous_playlist_item(player_id)
		end
	end
	
	def seek(position)
		vlc.seek(player_id, position)
	end
	
	def mediatype
		return currently_playing.mediatype
	end
	
	def title
		return currently_playing.name
	end
	
	def stop
		stopped = vlc.currently_playing(player_id)
		if stopped && resume
			item = vlc.server.database.media.by_path("=\"#{stopped.gsub("dvdsimple://", "")}\"").first
			if item && item.mediatype != Knots::ITEM_TYPE_IMAGE
				begin
					item.position = position && position > 0.01 && position < 0.98 ? position : 0
					item.save
					if (!@vlc.server.settings.resume_shot || @vlc.server.settings.resume_shot.to_i == 1) && item.position != 0 && ![Knots::ITEM_TYPE_AUDIO,Knots::ITEM_TYPE_IMAGE].include?(item.mediatype) && item.duration
						vlc.server.collection.grab_screenshot_for_item(item.id, item.position * item.duration)
					end
				rescue Exception => ex
				end
			end
		end
		save_session
		vlc.stop(player_id)
	end
	
	def save_session
		if @user && @user.admin && vlc.server.settings.save_session && vlc.server.settings.save_session.to_i == 1 && @names
			playlist = vlc.server.db.playlists.by_id(1).first
			playlist.resume_position = vlc.position(player_id)
			playlist.resume_index = vlc.playlistindex(player_id)
			if playlist && playlist.resume_position && playlist.resume_index
				vlc.server.db.playlist_items.delete_playlist_id(1)
				@names.each_with_index do | item, index |
					row = vlc.server.db.playlist_items.new
					row.playlist_id = 1
					row.media_id = item.id
					row.order_by = index + 1
					row.save
				end
				playlist.save
			else
				vlc.server.collection.reset_playlist(1)
			end
		end
	end
	
	def duration
		duration2 = vlc.duration(player_id)
		if duration2 && duration2.to_i > 0 && currently_playing.mediatype != Knots::ITEM_TYPE_IMAGE && (!currently_playing.duration || currently_playing.duration.to_i < duration2.to_i)
			vlc.server.log("Saving new duration to database for #{currently_playing.name}: #{currently_playing.duration ? Common.position_for_ffmpeg(currently_playing.duration) : "Unknown"} -> #{Common.position_for_ffmpeg(duration2)}", 2)
			mid = currently_playing.mid
			currently_playing.fields.delete("mid")
			currently_playing.duration = duration2
			currently_playing.save
			currently_playing.mid = mid
		end
		return currently_playing.duration
	end
	
	def media_id
		return currently_playing.id
	end
	
	def position
		vlc.position(player_id)
	end
	
	def ended?
		@end_count += 1 if position == nil
		return @end_count >= 5
		
	end
	
	def currently_playing
		@names[playlistindex - 1]
	end
	
	def currently_playing_filename
		vlc.currently_playing(player_id)
	end
	
	def video_width
		@width
	end
	
	def video_height
		@height
	end
	
	def buffer
		@buffer
	end
	
	def load_params(params)
		if params
			params.split(":").collect!{|p| p = p.split("=")}.each do | param |
				vlc.set_option(player_id, param[0], param[1] && param[1].index(" ") ? "\"#{param[1]}\"" : param[1]) if param.size == 2
			end
		end
	end
	
	def load_profile(item = nil)
		@port = vlc.next_free_port
		@mux = @profile.mux
		@buffer = @profile.buffer_seconds
		if @mux
			@stream = "stream.#{@profile.stream_extension || @mux}"
			if item && (!@profile.height || @profile.height == "") 
				@width, @height = Common.new_size_keeping_aspect(item.width, item.height, @profile.width, @profile.height, item.width || 640, item.height || 480)
			else
				@width = @profile.width
				@height = @profile.height
				if item
					@width = item.width if !@width
					@height = item.height if !@height
				end
			end
			quality = Array.new
			if !@profile.scale || @profile.scale.strip == ""
				aspect = (!vlc.server.settings.disable_aspect || vlc.server.settings.disable_aspect.to_i == 0) ? "vfilter=canvas{width=#{@width},height=#{@height},aspect=#{@width}:#{@height}}" : "maxwidth=#{@width},maxheight=#{@height}"
				quality.push("#{aspect}".split(",")) if @width && @height
			else
				if item
					@width = (item.width.to_f * @profile.scale) * 16 / 16
					@height = (item.height.to_f * @profile.scale) * 16 / 16
				end
				quality.push("scale=#{@profile.scale}")
			end
			quality.push("vcodec=#{@profile.video_format}") if @profile.video_format
			quality.push("vb=#{@profile.video_bitrate}") if @profile.video_bitrate
			quality.push("acodec=#{@profile.audio_format}") if @profile.audio_format
			quality.push("ab=#{@profile.audio_bitrate}") if  @profile.audio_bitrate
			quality.push("channels=#{@profile.audio_channels}") if  @profile.audio_channels
			quality.push("samplerate=#{@profile.audio_rate}") if  @profile.audio_rate
			quality.push("fps=#{@profile.fps}") if  @profile.fps
			quality.push("venc=#{@profile.video_encoder}") if  @profile.video_encoder
			quality.push("croptop=#{@profile.croptop}") if  @profile.croptop
			quality.push("cropbottom=#{@profile.cropbottom}") if  @profile.cropbottom
			quality.push("cropleft=#{@profile.cropleft}") if  @profile.cropleft
			quality.push("cropright=#{@profile.cropright}") if  @profile.cropright
			quality.push("threads=#{@profile.threads}") if  @profile.threads
			quality.push(@profile.extra) if  @profile.extra
			transcode = quality.size <= 5 ? "" : "transcode{#{quality.join(",")}}:"
			@width = 480 if !@width
			@height = 320 if !@height
			load_params(@profile.vlc_cmd_params)
			return "##{transcode}duplicate{dst=std{access=http,dst=:#{@port}/#{@stream},mux=#{@mux}},dst=rtp{sdp=rtsp://192.168.0.28:8080/stream.sdp}}"
      #return "##{transcode}duplicate{dst=std{access=http#{vlc.server.auth ? "{user=#{player_id},pwd=#{player_pass}}" : ""},dst=:#{@port}/#{@stream},mux=#{@mux}},dst=rtp{sdp=rtsp://192.168.0.28:8080/stream.sdp}}"
			#return "##{transcode}gather:std{access=http#{vlc.server.auth ? "{user=#{player_id},pwd=#{player_pass}}" : ""},dst=:#{@port}/#{@stream},mux=#{@mux}}"
      #return "##{transcode}duplicate{dst=std{access=http,dst=:#{@port}/#{@stream},mux=#{@mux}},dst=rtp{dst=192.168.0.28, sdp=rtsp://192.168.0.28:8080/stream.sdp}}"
		else
			@width = @profile.width || 480
			@height = @profile.height || 320
			if Common.osx?
				vlc.set_option(player_id, "enable-macosx-vout")
				vlc.set_option(player_id, "vout", "OpenGL")
			elsif Common.windows_os?
				vlc.set_option(player_id, "vout", "directx")
			else
				vlc.set_option(player_id, "vout", "xvideo")
			end
			vlc.set_option(player_id, "sout-transcode-soverlay")
			vlc.set_option(player_id, "freetype-fontsize", "12")
			vlc.set_option(player_id, "freetype-effect", "2")
			if vlc.server.settings.subtitle_font
				vlc.set_option(player_id, "freetype-font", vlc.server.settings.subtitle_font)
			end
			vlc.set_option(player_id, "fullscreen")
			return "#display"
		end
	end
	
	def mux
		@mux
	end
	
	def stream
		@stream
	end
	
	def port
		@port
	end
	
	def address
		@address
	end
end
