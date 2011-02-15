function add_torrent()
{
	torrent = document.getElementById('address').value;
	if (torrent != null)
	{
		new Ajax.Updater('torrentlist', '/torrent/add_torrent', {parameters: { address: torrent }});
	}
}

function remove_torrent(torrent)
{
	new Ajax.Updater('torrentlist', '/torrent/remove_torrent', {parameters: { torrent: torrent }});
}

function remove_complete()
{
	new Ajax.Updater('torrentlist', '/torrent/render_remove_complete', {});
}

function refresh_torrents()
{
	new Ajax.Updater('torrentlist', '/torrent/refresh_torrents', {});
}
