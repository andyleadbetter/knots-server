function datesForChannel(vdr, channel)
{
	if (document.getElementById('epg_' + channel, 'vdr').style.display != 'block')
	{
		document.getElementById('epg_' + channel, 'vdr').style.display = 'block';
		ajaxLoad('epg_' + channel, 'vdr', 'epg_dates', {vdr: vdr, channel: channel});
	}
	else
	{
		toggleVisibility('epg_' + channel);
	}
}

function programsForDate(vdr, channel, date)
{
	if (document.getElementById('epg_' + channel + '_' + date).style.display != 'block')
	{
		document.getElementById('epg_' + channel + '_' + date).style.display = 'block';
		ajaxLoad('epg_' + channel + '_' + date, 'vdr', 'epg_programs', {vdr: vdr, channel: channel, date: date});
	}
	else
	{
		toggleVisibility('epg_' + channel + '_' + date);
	}
}

function schedule(vdr, channel, date, time, program)
{
	new Ajax.Updater('', '/vdr/set_timer', {method: 'get', parameters: {vdr: vdr, channel: channel, date: date, time : time, program: program}, onComplete: function(){ alert_banner("Program scheduled.");}});
}

function searchEPG(event)
{
	if (!event || event.keyCode == 13)
	{
		val = document.getElementById('vdr_searchfield').value;
		waiting('epg', 'Searching');
		new Ajax.Updater('epg', '/vdr/search', {method:'get', parameters: { search: val,  }});
	
	}
}
