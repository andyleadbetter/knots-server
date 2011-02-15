click_time = new Date().getTime();

function timeClick()
{
	click_time = new Date().getTime();	
}

function removeDirectory()
{
	val = document.getElementById('scanned').value;
	if (val != null && val > 0)
	{
		toggleButtonDiv();
		waiting('mediadiv', 'Please wait');
		new Ajax.Updater('mediadiv', '/root/media', {parameters: { rmdir: val }});
		toggleButtonDiv();
	}
}

function addPVR()
{
	lightbox("/root/pvr");	
}

function browseList(category, tag, value, virtual, page)
{
	sort = document.getElementById('sort').value;
	id = "";
	if (tag == null && value == null && virtual == null)
		id = 'cat_' + category;
	else
	if (value == null && virtual == null)
		id = 'tag_' + tag;
	else
	if (virtual == null)
		id = 'value_' + value;
	else
		id = 'virt_' + virtual;
	if (document.getElementById(id) != null)
	{
		if (document.getElementById(id).style.display != 'block' || page != null)
		{
			if (page == null)
				page = 1;
			document.getElementById(id).style.display = 'block';
			ajaxLoad(id, 'root', 'browse_main', {category: category, tag: tag, value: value, virtual: virtual, view: 0, order: sort, div: id, page: page});
		}
		else
		{
			document.getElementById(id).style.display = 'none';
		}
	}
}


function changeView()
{
	val = document.getElementById('view').value;
	if (val != null)
	{
		new Ajax.Updater('void', '/root/change_view', {method: 'get', parameters: {view: val}});
		ajaxLoad('browse_content', 'root', 'browse_main', {view: val});
	}
}

function removePVR(id)
{
	if (confirm("Are you sure you want to remove this pvr?"))
		lightbox("/root/pvr?remove=" + id);	
}

function showPVR(id)
{
	for (i = 0; i < 4; i++)
	{
		document.getElementById('pvr' + i).style.display = id == i ? 'block' : 'none';	
	}
}

function changeShareProfile(id)
{
	val = document.getElementById('share_tp').value;
	new Ajax.Updater('void', '/root/change_share_profile', {method: 'get', parameters: {share: id, profile: val}});	
}

function savePVR(id)
{
	types = new Array("vdr", "mythtv", "dreambox", "dbox2_");
	new Ajax.Updater('void', '/root/pvr', {method: 'get', parameters: {settings: pvrSettings(id), save: types[id]}, onComplete: function(){ addPVR() }});
}

function testPVR(id)
{
	waiting("test_pvr" + id, "Please wait.")
	new Ajax.Updater('test_pvr' + id, "/root/test_pvr", {method: 'get', parameters: {pvr: id, settings: pvrSettings(id)}, evalScripts: true});
}

function pvrSettings(id)
{
	settings = new Array();
	amounts = new Array(4, 5, 6, 5);
	for (i = 0; i < amounts[id]; i++)
	{
		settings[i] = document.getElementById('pvr' + id + '_' + i).value;	
	}
	return settings.join(",");
}

function selectCategory()
{
	val = document.getElementById('categories').value;
	if (val != null && val > 0)
	{
		new Ajax.Updater('images_fieldset', '/root/update_category_tag_image', {parameters: { id: val, type: 'categories' }, evalScripts: true});
	}
}

function exportProfile(id)
{
	document.location = '/root/export_profile?id=' + id;
}

function reloadProfile(id)
{
	waiting('profile_' + id, 'Please wait');
	new Ajax.Updater('profile_' + id, '/root/reload_profile', {parameters: { id: id }, evalScripts: true});
}

function selectPlaylistCategory()
{
	val = document.getElementById('plcat').value;
	if (val != null && val != "-")
	{
		document.getElementById('pldiv').style.display = 'block';
		new AjaxUpload('upload_button3', {action: '/root/import_playlist', data: {plcat: val}, onComplete: function(file, response) {alert_banner('Playlist imported')}});
	}
	else
		document.getElementById('pldiv').style.display = 'none';
}

function removeShare(id)
{
	if (confirm("Are you sure you want to remove this share?"))
	{
		waiting('sharesdiv', 'Please wait');
		new Ajax.Updater('sharesdiv', '/root/show_shares', {parameters: { remove: id }});
	}
}

function checkServerAccessibility()
{
	waiting('checkdynresult', 'Please wait');
	document.getElementById('checkdynbtn').style.display = 'none';
	new Ajax.Updater('checkdynresult', '/root/check_server_accessibility', {method: 'get', onComplete: function(){ document.getElementById('checkdynbtn').style.display = 'block'; }});
}

function registerDynKnots()
{
	username = document.getElementById('dynknotsuser').value;
	password = document.getElementById('dynknotspwd').value;
	password2 = document.getElementById('dynknotspwd2').value;
	if (username == null || password == null || username.length < 6 || password.length < 6 || username.match(/^\w+$/) == null || password.match(/^\w+$/) == null)
	{
		alert_banner('Too short username or password. Please use at least 6 letters and letters a-z and A-Z.')	
	}
	else
	if (password != password2)
	{
		alert_banner("Passwords don't match.")	
	}
	else
	{
		waiting('dynknotsinfo', 'Loading');
		new Ajax.Updater('dynknotsinfo', '/root/dynknots_register', {method:'get', evalScripts: true, parameters: { user: escape(username), password: escape(password)}});	
	}
}

function loginDynKnots()
{
	username = document.getElementById('dynknotsuser').value;
	password = document.getElementById('dynknotspwd').value;
	if (username == null || password == null || username.length < 6 || password.length < 6 || username.match(/^\w+$/) == null || password.match(/^\w+$/) == null)
	{
		alert_banner('Too short username or password.')	
	}
	else
	{
		waiting('dynknotsinfo', 'Loading');
		new Ajax.Updater('dynknotsinfo', '/root/dynknots_login', {method:'get', evalScripts: true, parameters: { user: escape(username), password: escape(password)}});	
	}
}

function selectTagValue()
{
	val = document.getElementById('tag_values').value;
	if (val != null && val > 0)
	{
		new Ajax.Updater('images_fieldset', '/root/update_category_tag_image', {parameters: { id: val, type: 'tag_values' }, evalScripts: true});
	}
}

function reloadVirtualCategoryImage(id)
{
	new Ajax.Updater('virtual_image_' + id, '/root/reload_virtual_image', {parameters: { id: id }, evalScripts: true});
}

function deleteVirtualCategoryImage(id)
{
	if (confirm("Are you sure you want to delete this image?"))
		new Ajax.Updater('virtual_image_' + id, '/root/reload_virtual_image', {parameters: { id: id, del: true }, evalScripts: true});
}

function deleteImage(type)
{
	val = document.getElementById(type).value;
	if (val != null && val > 0 && confirm("Are you sure you want to delete this image?"))
	{
		new Ajax.Updater('images_fieldset', '/root/update_category_tag_image', {parameters: { type: type, id: val, del: true }, evalScripts: true});
	}
}

function showPathCategories()
{
	val = document.getElementById('scanned').value;
	if (val != null && val != "" && val != -1)
	{
		waiting("path_categories", "Loading");
		new Ajax.Updater('path_categories', '/root/path_categories', {parameters: { id: val }});	
	}
}

function changePassword()
{
	user = document.getElementById('userlist').value;
	pass = document.getElementById('passwd').value;
	role = document.getElementById('role').value;
	if (user != null && user != -1 && user != "" && pass != "" && role != null)
	{
		new Ajax.Updater('voiddiv', '/root/change_password', {method: 'get', parameters: {userid: user, password: pass, role: role}, onComplete: function(){ alert_banner('Password changed. Press refresh to relogin if you are logged in as this user.') }});
	}

}

function addUser()
{
	username = prompt("Enter username:");
	if (username != null)
	{
		new Ajax.Updater('usersdiv', '/root/users', {parameters: { add_user: username }});	
	}
}

function deleteUser()
{
	user = document.getElementById('userlist').value;
	if (user != null && user != -1 && user != "")
	{
		warning = "Are you sure you want to delete this user?";
		if (document.getElementById('userlist').length == 1)
			warning += " Deleting the last user will disable authentication and allow anyone to access the server with admin rights.";
		if (confirm(warning))
		{
			new Ajax.Updater('usersdiv', '/root/users', {parameters: { delete_user: user }});	
		}
	}
}


function addCategoryRights()
{
	user = document.getElementById('userlist').value;
	rights = document.getElementById('all_categories').value;
	if (user != null && rights != null && rights != -1)
	{
		new Ajax.Updater('userinfo', '/root/users', {parameters: { show: user, add_category: rights }});	
	}
}

function removeCategoryRights()
{
	user = document.getElementById('userlist').value;
	rights = document.getElementById('user_categories').value;
	if (user != null && rights != null && rights != -1)
	{
		new Ajax.Updater('userinfo', '/root/users', {parameters: { show: user, remove_category: rights }});	
	}
}


function selectUser()
{
	val = document.getElementById('userlist').value;
	if (val != null && val != -1 && val != "")
	{
		new Ajax.Updater('userinfo', '/root/users', {parameters: { show: val }});
	}
}

function changeCategoryForPath(path_id, type)
{
	val = document.getElementById('path_category' + type).value;
	if (val != null)
	{
		new Ajax.Updater('voiddiv', '/root/path_categories', {parameters: { path_id: path_id, type: type, category: val }});
	}
}

function addDirectory()
{
	lightbox("/root/dirbrowser");
}

function addScanDirectory(dir)
{
	new Ajax.Updater('mediadiv', '/root/media', {parameters: { adddir: dir }});
	alert_banner('Added to list of scanned folders.')	
}

function switchToDir(dir)
{
	new Ajax.Updater('dirbrowser', '/root/dirbrowser', {parameters: { dir: dir, hidden: document.getElementById('hidden_dirs').checked }});	
}

function switchToNewDir(dir)
{
	val = prompt("Path", dir);
	if (val != null)
		new Ajax.Updater('dirbrowser', '/root/dirbrowser', {parameters: { dir: val, hidden: document.getElementById('hidden_dirs').checked }});	
}

function addCategory()
{
	val = prompt("Enter category name", "");
	if (val && val.length > 0)
	{
		new Ajax.Updater('categories_fieldset', '/root/edit_categories', {parameters: { add: val }});
	}	
}

function getAddress()
{
	remote = location.host;
	if (remote.indexOf(":") != -1)
		remote = remote.substring(0, remote.indexOf(":"))
	return remote;	
}

function renameCategory()
{
	val = document.getElementById('categories').value;
	if (val && val > 0)
	{
		val2 = prompt("Rename category", document.getElementById('categories').options[document.getElementById('categories').selectedIndex].text);
		if (val2 != null)
			new Ajax.Updater('categories_fieldset', '/root/edit_categories', {parameters: { rename: val, to: val2 }});
	}
}

function reloadImage(type)
{
	if (type == "categories")
		selectCategory();
	else
	if (type == "tags")
		selectTag();
	else
		selectTagValue();
}

function removeCategory()
{
	val = document.getElementById('categories').value;
	if (val && val > 0)
	{
		new Ajax.Updater('categories_fieldset', '/root/edit_categories', {parameters: { remove: val }});
	}
}

function selectTag()
{
	val = document.getElementById('tags').value;
	new Ajax.Updater('tags_fieldset', '/root/edit_tags', {parameters: { selected: val }, evalScripts: true});
	new Ajax.Updater('images_fieldset', '/root/update_category_tag_image', {parameters: { id: val, type: 'tags' }, evalScripts: true});
}

function addTag()
{
	val = prompt("Enter new tag", "");
	if (val && val.length > 0)
	{
		new Ajax.Updater('tags_fieldset', '/root/edit_tags', {parameters: { add: val }});
	}
}

function addSetting()
{
	desc = prompt("Description:");
	if (desc != null && desc != "")
	{
		key = prompt("Key:");
		if (key != null && key != "")
		{
			value = prompt("Value:");
			if (value != null && value != "")
			{
				ajaxLoad('settingsdiv', 'root', 'options', {desc: desc, key: key, value: value});

			}
		}
	}
}

function resetSettings()
{
	if (confirm("Are you sure you want to reset settings?"))
	{
		ajaxLoad('settingsdiv', 'root', 'options', {reset: true});
	
	}
}

function resetVirtualCategories()
{
	if (confirm("Are you sure you want to reset virtual categories?"))
	{
		ajaxLoad('virtualsdiv', 'root', 'reset_virtual_categories', {});
	
	}
}


function renameTag()
{
	val = document.getElementById('tags').value;
	if (val && val > 0)
	{
		val2 = prompt("Rename tag", document.getElementById('tags').options[document.getElementById('tags').selectedIndex].text);
		if (val2 != null)
			new Ajax.Updater('tags_fieldset', '/root/edit_tags', {parameters: { rename: val, to: val2 }});
	}
}

function renameTagValue()
{
	val = document.getElementById('tag_values').value;
	if (val && val > 0)
	{
		val2 = prompt("Rename value", document.getElementById('tag_values').options[document.getElementById('tag_values').selectedIndex].text);
		if (val2 != null)
			new Ajax.Updater('tags_fieldset', '/root/edit_tags', {parameters: { rename_value: val, to: val2 }});
	}
}



function removeTagValue()
{
	val = document.getElementById('tag_values').value;
	val2 = document.getElementById('tags').value;
	if (val && val > 0 && confirm("Are you sure you want to remove this value?"))
	{
		new Ajax.Updater('tags_fieldset', '/root/edit_tags', {parameters: { selected: val2, remove_value: val }});
	}
}

function addTagValue()
{
	val = document.getElementById('tags').value;
	if (val && val > 0)
	{
		val2 = prompt("Enter new value for this tag", "");
		if (val2 && val2.length > 0)
		{
			new Ajax.Updater('tags_fieldset', '/root/edit_tags', {parameters: { tag: val, value: val2 }});
		}
	}
}


function removeTag()
{
	val = document.getElementById('tags').value;
	if (val && val > 0 && confirm("Are you sure you want to remove this tag?"))
	{
		new Ajax.Updater('tags_fieldset', '/root/edit_tags', {parameters: { remove: val }});
	}
}

function fetchLyrics(id)
{
	ajaxLoad('lyrics', 'root', 'fetch_lyrics', {id: id});	
}

function showItemTags(id)
{
	ajaxLoad('lyrics', 'root', 'show_item_tags', {id: id});
}

function searchBy(name)
{
	document.getElementById('searchfield').value = name;
	search2(null);
}

function searchBy2(name)
{
	document.getElementById('edit_searchfield').value = name;
	search(null);
}

function showHelp()
{
	if (document.getElementById('helpdiv').style.display != 'block')
	{
		document.getElementById('helptoggle').innerHTML = 'Learn less';
	}
	else
	{
		document.getElementById('helptoggle').innerHTML = 'Learn more';
	}
	toggleVisibility('helpdiv');
}

function createPlaylist(stream)
{
	if (confirm("Stop playback in browser?"))
		document.getElementById('player_container').innerHTML = '';
	document.location='/root/stream_as_playlist?stream=' + escape(stream);	
}

function randomVideos()
{
	waiting('browse_content', 'Loading');
	new Ajax.Updater('browse_content', '/root/random_videos', {method:'get'});

}

function search(event)
{
	if (!event || event.keyCode == 13)
	{
		document.getElementById('toggle_button').value = "Select all";	
		val = document.getElementById('edit_searchfield').value;
		ignored = document.getElementById('ignore').checked;
		if (true || val.length > 0)
		{
			waiting('videoitems', 'Searching');
			new Ajax.Updater('videoitems', '/root/search_videos', {method:'get', parameters: { search: val, ignore: ignored, category: document.getElementById('categories').value, tag: document.getElementById('tags').value, tag_value: document.getElementById('tag_values').value, search_limit: document.getElementById('search_limit').value}});
		}
	}
}

function savePlaylist(playlist_id, playlist_name)
{
	playlist_name = prompt("Playlist name:", playlist_name)
	if (name != null)
	{
		new Ajax.Updater('light', '/root/save_playlist', {method:'get', evalScripts: true, parameters: { id: playlist_id, name : playlist_name }});			
	}
}

function removePlaylistItem(item_id)
{
	new Ajax.Updater('light', '/root/remove_playlist_item', {method:'get', evalScripts: true, parameters: { id: item_id }});	
}


function deletePlaylist(playlist_id)
{
	if (confirm("Are you sure you want to delete this playlist?"))
	{
		new Ajax.Updater('light', '/root/delete_playlist', {method:'get', evalScripts: true, parameters: { id: playlist_id }, onComplete: function(){ reloadPlaylists(null); }});
	}
}

function fireAndForget(url, params)
{
	new Ajax.Request(url, {parameters: params });
}

function addToPlaylist(media_id)
{
	fireAndForget("/root/add_to_playlist", {id : media_id, playlist : document.getElementById('playlist').value});
	$('item_' + media_id).highlight();
}

function search2(event, pagenumber)
{
	if (!event || event.keyCode == 13)
	{
		val = document.getElementById('searchfield').value;
		if (pagenumber == null)
			pagenumber = 1;
		waiting('browse_content', 'Searching');
		new Ajax.Updater('browse_content', '/root/browse', {method:'get', parameters: { search: val, view: document.getElementById('view').value, order : document.getElementById('sort').value, page : pagenumber }});
	}
}

function showPlaylist()
{
	//new Ajax.Updater('light', '/root/playlist', {method:'get', evalScripts: true, parameters: { id: document.getElementById('playlist').value }});
	lightbox("/root/playlist?id=" + document.getElementById('playlist').value);
	
}

function searchTheMovieDB(event, mediaid)
{
	if (!event || event.keyCode == 13)
	{
		val = document.getElementById('themoviedbsearch').value;
		if (val.length > 3)
		{
			waiting('light', 'Searching');
			new Ajax.Updater('light', '/root/themoviedb', {method:'get', parameters: { search: val, id: mediaid}});
		}
	}
}

function elementX(obj)
{
	var curleft = curtop = 0;
	if (obj.offsetParent)
	{
		do
		{
			curleft += obj.offsetLeft;
			curtop += obj.offsetTop;
		} 
		while (obj = obj.offsetParent);
	}
	return curleft;
}

function seek(e, player_id)
{
	var posx = 0;
	var posy = 0;
	if (!e) var e = window.event;
	if (e.pageX || e.pageY) 	{
		posx = e.pageX;
		posy = e.pageY;
	}
	else if (e.clientX || e.clientY) 	{
		posx = e.clientX + document.body.scrollLeft
			+ document.documentElement.scrollLeft;
		posy = e.clientY + document.body.scrollTop
			+ document.documentElement.scrollTop;
	}
	x = posx - elementX(document.getElementById('progress')) - 20;
	w = document.getElementById('progress').style.width;
	position = x / w.substring(0, w.indexOf("px"));
	new Ajax.Updater('progress', '/root/seek', {method: 'get', parameters: {position: position, id: player_id}});
}

function lightbox(url)
{
	waiting('light', 'Loading');
	document.getElementById('light').style.display='block';
	document.getElementById('fade').style.display='block';
	new Ajax.Updater('light', url, {method: 'get', evalScripts: true});
}

function playerLightbox(url)
{
	closeLightbox();
	if (document.getElementById('light_player').style.visibility == 'hidden')
	{
		stopPlayback(player_id, poller, null);
		document.getElementById('fade_player').style.visibility = 'visible';
		document.getElementById('light_player').style.visibility = 'visible';
		document.getElementById('light_player').style.display='block';
		document.getElementById('fade_player').style.display='block';
		waiting('light_player', 'Waiting for old stream to stop');
		setTimeout("playerLightbox(\"" + url + "\")", 1000);
		return;
	}
	waiting('light_player', 'Loading');
	document.getElementById('light_player').style.display='block';
	document.getElementById('fade_player').style.display='block';
	new Ajax.Updater('light_player', url, {method: 'get', evalScripts: true});
	
}

function waiting(divname, message)
{
	document.getElementById(divname).innerHTML = "<div class=\"waiting\"><img src=\"/root/resource_file?type=image&file=waiting.gif\" /> " + message + "</div>";	
}

function closeLightbox()
{
	document.getElementById('light').innerHTML = "";
	document.getElementById('light').style.display='none';
	document.getElementById('fade').style.display='none';
}

function closePlayerLightbox()
{
	document.getElementById('light_player').innerHTML = "";
	document.getElementById('light_player').style.display='none';
	document.getElementById('fade_player').style.display='none';
}

function updateDatabase()
{
	toggleButtonDiv();
	poller = poll("mediacount", "root", "mediacount", 10, {});
	new Ajax.Updater('mediadiv', '/root/update_database', {method: 'get', onComplete: function(){ poller.stop(); }});
}

function abortScanning()
{
	new Ajax.Updater('void', '/root/abort_scanning', {method: 'get'});
}

function updateSelected()
{
	val = document.getElementById('scanned').value;
	if (val != null && val.length > 0)
	{
		toggleButtonDiv();
		poller = poll("mediacount", "root", "mediacount", 10, {});
		new Ajax.Updater('mediadiv', '/root/update_database?id=' + val, {method: 'get', onComplete: function(){ poller.stop(); }});
	}
}

function updateMythTVRecordings()
{
	toggleButtonDiv();
	poller = poll("mediacount", "root", "mediacount", 10, {});
	new Ajax.Updater('mediadiv', '/root/update_database?myth=1', {method: 'get', onComplete: function(){ poller.stop(); }});
}

function updateVDRChannels()
{
	toggleButtonDiv();
	poller = poll("mediacount", "root", "mediacount", 10, {});
	new Ajax.Updater('mediadiv', '/root/update_database?vdr=1', {method: 'get', onComplete: function(){ poller.stop(); }});
}

function updateDreamboxChannels()
{
	toggleButtonDiv();
	poller = poll("mediacount", "root", "mediacount", 10, {});
	new Ajax.Updater('mediadiv', '/root/update_database?dreambox=1', {method: 'get', onComplete: function(){ poller.stop(); }});
}

function updateDBox2Channels()
{
	toggleButtonDiv();
	poller = poll("mediacount", "root", "mediacount", 10, {});
	new Ajax.Updater('mediadiv', '/root/update_database?dbox2=1', {method: 'get', onComplete: function(){ poller.stop(); }});
}

function applyToSelected()
{
	$('search_form').request({onComplete: function(){ alert_banner('Action applied!') }});	
}

function sendBugreport()
{
	document.getElementById('bugsendbutton').style.display = 'none';
	new Ajax.Updater('bugthanks', 'http://nakkiboso.com/knots/issues.php', {method: 'post', parameters: {problem: document.getElementById('problem').value}, onComplete: function(){ alert_banner('Report sent. Thank you!') }});
}

function saveInfo(id)
{
	$('item_form').request({onComplete: function(){ lightbox('/root/show_video?id=' + id) }});	
}

function newTranscodingProfile()
{
	val = prompt("Name of the profile", "");
	if (val != null)
	{
		new Ajax.Updater('transcodingdiv', '/root/edit_transcoding_profile', {method: 'get', parameters: {add: val}, evalScripts: true});	
	}
}

function resetTranscodingProfiles()
{
	if (confirm("Are you sure you want to reset your transcoding profiles? This will remove all your modifications and reload the default ones?"))
	{
		new Ajax.Updater('transcodingdiv', '/root/reset_transcoding_profiles', {method: 'get', parameters: {}, evalScripts: true});	
	}
}

function newVirtualCategory()
{
	val = prompt("Name of the category", "");
	if (val != null)
	{
		new Ajax.Updater('virtualsdiv', '/root/save_virtual_category', {method: 'get', parameters: {add: val}});	
	}
}

function showPlayer(visibility)
{
	document.getElementById('light_player').style.visibility = (visibility ? 'visible' : 'hidden');
	document.getElementById('fade_player').style.visibility = (visibility ? 'visible' : 'hidden');
}

function play(id)
{
	playerLightbox('/root/play?id=' + id + '&profile=' + document.getElementById('transcoding_profile').value)
	showPlayerButton(true);	
}

function playAlbum(id)
{
	playerLightbox('/root/play_album?id=' + id + '&profile=' + document.getElementById('transcoding_profile').value)
	showPlayerButton(true);
}

function playArtist(id)
{
	playerLightbox('/root/play_artist?id=' + id + '&profile=' + document.getElementById('transcoding_profile').value)
	showPlayerButton(true);	
}

function showPlayerButton(mode)
{
	if (document.getElementById('player_back') != null)
		document.getElementById('player_back').innerHTML = mode ? '<a href="#" onclick="showPlayer(true);return false;"><span>Return to player</span></a>' : '';	
}

function playPlaylistItem(id)
{
	val = document.getElementById('playlist_items').value;
	new Ajax.Updater('playing', '/root/play_playlist_item', {method: 'get', parameters: {id: id, index: val}, onComplete: function(){ updateProgress(id) }});	
}

function previousPlaylistItem(id)
{
	new Ajax.Updater('playing', '/root/previous_playlist_item', {method: 'get', parameters: {id: id}, onComplete: function(){ updateProgress(id) }});	
}

function nextPlaylistItem(id)
{
	new Ajax.Updater('playing', '/root/next_playlist_item', {method: 'get', parameters: {id: id}, onComplete: function(){ updateProgress(id) }});	
}

function updatePlaying(id)
{
	new Ajax.Updater('playing', '/root/update_playing', {method: 'get', parameters: {id: id}});	
}

function updateProgress(id)
{
	new Ajax.Updater('progress', '/root/progress', {method: 'get', parameters: {id: id}});
}

function playPlaylist(id)
{
	playerLightbox('/root/play?playlist_id=' + id + '&profile=' + document.getElementById('transcoding_profile').value)	
}

function shufflePlaylist(id)
{
	new Ajax.Updater('light', '/root/shuffle_playlist', {method:'get', evalScripts: true, parameters: { id: id}});
}

function saveProfile()
{
	fireAndForget("/root/save_profile", {id: document.getElementById('transcoding_profile').value});	
}

function browseTags(category, id)
{
	ajaxLoad('browse_tags', 'root', 'browse', {category_id: category, tag: id});return false;	
}

function byPath(path, pagenumber)
{
	ajaxLoad('browse_content', 'root', 'browse_by_path', {path: path, view: document.getElementById('view').value, order : document.getElementById('sort').value, page: pagenumber});return false;	
}

function browseValues(category, id)
{
	ajaxLoad('browse_values', 'root', 'browse', {category_id: category, value: id});return false;	
}

function browseCategory(category, tag_id, value_id, pagenumber)
{
	params = {category: category, view: document.getElementById('view').value, order : document.getElementById('sort').value, page : pagenumber};
	if (tag_id && tag_id != null)
			params["tag_id"] = tag_id;
	if (value_id && value_id != null)
		params["value_id"] = value_id;
	ajaxLoad('browse_content', 'root', 'browse', params);	
}

function browseVirtual(id, page)
{
	ajaxLoad('browse_content', 'root', 'show_virtual', {vid: id, page: page, order: document.getElementById('sort').value});	
}

function browseMain()
{
	ajaxLoad('browse_content', 'root', 'browse_main', {});	
}

function removeTagValueFromMedia(mediatag_id, media_id)
{
	ajaxLoad('tags_edit', 'root', 'remove_tag_value_from_media', {edit: media_id, mediatag_id: mediatag_id});
}

function saveTranscodingProfile(profile_id)
{
	$('transcodingform_' + profile_id).request({parameters : {id : profile_id}, onComplete: function(){ alert_banner('Profile saved!') }});	
}

function saveVirtualCategory(category_id)
{
	$('virtual_category_form_' + category_id).request({parameters : {id : category_id}, onComplete: function(){ alert_banner('Profile saved!') }});	
}

function addTagValueToMedia(media_id)
{
	tag = document.getElementById('tag').value;
	value = document.getElementById('value').value;
	if (tag != "" && value != "")
	{
		ajaxLoad('tags_edit', 'root', 'add_tag_value_to_media', {edit: media_id, tag: tag, tag_value: value});
	}
}

function deleteTranscodingProfile(profile_id)
{
	if (confirm("Are you sure you want to delete this transcoding profile?"))
	{
		new Ajax.Updater('transcodingdiv', '/root/edit_transcoding_profile', {method: 'get', parameters: {del: profile_id}});	
	}
}

function deleteVirtualCategory(category_id)
{
	if (confirm("Are you sure you want to delete this virtual category?"))
	{
		new Ajax.Updater('virtualsdiv', '/root/save_virtual_category', {method: 'get', parameters: {del: category_id}});	
	}
}

function forceStop(player_id, div_id)
{
	new Ajax.Updater('', '/root/stop', {method: 'get', evalScripts: true, parameters: {id: player_id}, onComplete:function(request){ ajaxLoad('main_' + div_id, 'root', 'server_status', {index: div_id});}});
	showPlayerButton(false);	
}

function stopPlayback(player_id, poller, id)
{
	if (poller != null)
		poller.stop();
	if (document.getElementById('vlc') != null)
	{
		document.getElementById('vlc').style.visibility = 'hidden';
	}
	closePlayerLightbox();
	if (id)
	{
		new Ajax.Updater('', '/root/stop', {method: 'get', evalScripts: true, parameters: {id: player_id}, onComplete:function(request){reloadItem(id);}});
	}
	else
		fireAndForget('/root/stop', {id: player_id});
	showPlayerButton(false);
}

function addFromYoutube()
{
	url = document.getElementById('youtube_url').value;
	if (url != null && url.indexOf("watch?") != -1)
	{
		ajaxLoad('videoitems', 'root', 'add_from_youtube', {url: url, type: document.getElementById('youtube_type').value});
	}
}

function addNewItem()
{
	url = document.getElementById('new_url').value;
	if (url != null && url.indexOf("://") != -1)
	{
		ajaxLoad('videoitems', 'root', 'add_new_item', {url: url, type: document.getElementById('new_type').value, category: document.getElementById('new_category').value,name: document.getElementById('new_name').value});
	}
}

function grabScreenshot(item)
{
	spot = null;
	time = new Date().getTime() - click_time;
	if (time > 1000)
		spot = prompt("Grab screenshot from?", "00:01:00");
	waiting('screenshot_' + item, 'Grabbing');
	new Ajax.Updater('screenshot_' + item, '/root/grab_screenshot', {method: 'get', parameters: {id: item, spot: spot}});
}

function updateScreenshot(item)
{
	new Ajax.Updater('screenshot_' + item, '/root/update_screenshot', {method: 'get', parameters: {id: item}});
}


function poll(div, plugin, method, interval, params)
{
	return new Ajax.PeriodicalUpdater(div, "/" + plugin + "/" + method, {
	 // initial number of seconds interval between calls
	 frequency : interval,
	 decay : 2,
	 evalJS : true,
	 evalScripts : true,
	 parameters : params
	});	
}

function deactivateItem(item)
{
	if (confirm("Do you really want to deactivate this item?"))
	{
		closeLightbox();
		new Ajax.Updater('light', '/root/delete_item', {method: 'get', parameters: {id: item}});
	}
}

function vacuumDatabase()
{
	if (confirm("Do you really want to clean up the collection? This will delete all unused tags, values, images and vacuums the database."))
	{
		toggleButtonDiv()
		new Ajax.Updater('mediadiv', '/root/vacuum_database');
	}
}

function saveSettings()
{
	$('settings_root').request({onComplete: function(){ajaxLoad('settingsdiv', 'root', 'options'); }});
	waiting('settingsdiv', 'Saving settings.');	
}

function saveTheMovieDBTags()
{
	$('moviedbform').request({onComplete: function(){lightbox('/root/show_video?id=' + document.getElementById('saveid').value)}});	
}

function ajaxLoad(div, plugin, method, params)
{
	waiting(div, 'Loading');
	new Ajax.Updater(div, '/' + plugin + '/' + method, {method: 'get', evalScripts: true, parameters: params});
}

function openPage(index, plugin, method)
{
	i = 0;
	while (document.getElementById('main_' + i) != null)
	{
		document.getElementById('main_' + i).style.visibility = 'hidden';
		document.getElementById('main_' + i).style.display = 'none';
		i += 1;
	}
	document.getElementById('main_' + index).style.display = 'block';
	document.getElementById('main_' + index).style.visibility = 'visible';
	if (plugin == "root" && method == "server_status")
	{
		ajaxLoad("main_" + index, plugin, method, {index: index})	
	}
}

function toggleButtonDiv()
{
	toggleVisibility('buttonsdiv');
	toggleVisibility('waitingdiv');	
}

function selectAllSearchResults(clicked)
{
	clicked.checked = !clicked.checked;
	i = 0;
	while (document.getElementById('checkid_' + i) != null)
	{
		document.getElementById('check_' + document.getElementById('checkid_' + i).value).checked = clicked.checked;
		i += 1;
	}
}

function fetchAlbumCovers()
{
	ajaxLoad('videoitems', 'root', 'fetch_album_covers', {});	
}

function fetchMovieInfo()
{
	if (confirm("Are you sure you want to fetch movie info for all your movies? It can take several minutes to finish."))
		ajaxLoad('videoitems', 'root', 'fetch_movie_info', {});	
}

function toggleSelected()
{
	val = document.getElementById('toggle_button').value == "Select all";
	i = 0;
	while (document.getElementById('checkid_' + i) != null)
	{
		document.getElementById('check_' + document.getElementById('checkid_' + i).value).checked = val;
		i += 1;
	}
	document.getElementById('toggle_button').value = val ? "Select none" : "Select all";
}

function tagsForCategory(id)
{
	ajaxLoad("browse_content", "root", "browse", {category: id})
}

function browseByTags(id)
{
	if (id == -1)
		ajaxLoad('browse_content', 'root', 'browse', {tags: id, view: document.getElementById('view').value, order : document.getElementById('sort').value, page : 1});
	else
		ajaxLoad('tag_' + id, 'root', 'browse', {tags: id, view: document.getElementById('view').value, order : document.getElementById('sort').value, page : 1});
}

function showTagValues(tag_id, id)
{
	ajaxLoad('value_' + id, 'root', 'browse', {tag: tag_id, value: id, view: document.getElementById('view').value, order : document.getElementById('sort').value, page : 1});
}

function alert_banner(val)
{
	document.getElementById('banner').innerHTML = val;
	document.getElementById('banner').style.display = 'block';
	setTimeout("document.getElementById('banner').style.display = 'none';", 3000);
}

function reloadItem(id)
{
	if (document.getElementById('item_' + id) != null)
	{
		waiting('item_' + id, 'Loading');
		new Ajax.Updater('item_' + id, '/root/reload_item', {method: 'get', parameters: {id: id, force: 'true'}});
	}
}

function removeResumepoint(id)
{
	if (id != null)
		new Ajax.Updater('void', '/root/remove_resumepoint', {method: 'post', evalScripts: true, parameters: {id: id}, onComplete: function(){ reloadItem(id);}});
}

function rate(id, rating)
{
	new Ajax.Updater('stars_' + id, '/root/rate', {method: 'get', parameters: {id: id, rating: rating}});	
}

function toggleVisibility(divname)
{
	if (document.getElementById(divname).style.display != 'none')
	{
		document.getElementById(divname).style.display = 'none';
	}
	else
	{
		document.getElementById(divname).style.display = 'block';
	}
}

function newPlaylist()
{
	val = prompt("Playlist name");
	if (val != null && val.length > 0)
	{
		new Ajax.Updater('void', '/root/new_playlist', {method: 'post', evalScripts: true, parameters: {plname: val}, onComplete: function(){ reloadPlaylists(val); }});
	}
}

function reloadPlaylists(selected)
{
	new Ajax.Updater('playlist', '/root/reload_playlists', {method: 'get', evalScripts: true, parameters: {select_playlist: selected}});

}

function shareItem(media_id, playlist_id)
{
	document.getElementById('light').style.display = 'block';
	document.getElementById('fade').style.display = 'block';
	new Ajax.Updater('light', '/root/share_item', {method: 'get', evalScripts: true, parameters: {media: media_id, playlist: playlist_id}});
}

function playShare(key)
{
	document.getElementById('light_player').style.display = 'block';
	document.getElementById('fade_player').style.display = 'block';
	profile = document.getElementById('transcoding_profile').value;
	ajaxLoad("light_player", "root", "play_share", {key: key, profile: profile})
	
}


function copyToClipboard(str)
{
	ZeroClipboard.setMoviePath('/root/resource_file?type=image&file=zeroclipboard.swf');
	var clip = new ZeroClipboard.Client();
	clip.setText(str);
	clip.glue( 'd_clip_button', 'd_clip_container' );
	clip.show();
	alert(clip.clipText);
}

function themoviedb(id)
{
	id = document.getElementById('id').value;
	if (name != null)
	{
		waiting('light', 'Loading');
		new Ajax.Updater('light', '/root/themoviedb', {method: 'get', parameters: {id: id}});
	}
}

function opensubtitles(id)
{
	waiting('light', 'Loading');
	new Ajax.Updater('light', '/root/search_subs', {method: 'get', parameters: {id: id}});
}

function downloadSub(media_id, sub_id, extname)
{
	waiting('light', 'Downloading');
	new Ajax.Updater('light', '/root/download_sub', {method: 'get', parameters: {media_id: media_id, sub_id: sub_id, extname: extname}});
}

function load_complete(plugin, method)
{
	if (plugin == "root" && method == "latest")
	{
		addReflections();
	}
}
