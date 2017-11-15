# * Исправить анимацию текущего трека после синхронизации.
# * Исправить отображение столбцов списке треков.
# * Исправить меню в трее.

{Δimport, Δexport, repack, iif}	= require('./util.coffee')
{Record, PlayList, MusicBox}	= require('./music.coffee')
require('clr').init assemblies:
	['System', 'mscorlib', 'PresentationFramework', 'WindowsBase'
	'Microsoft.VisualBasic', 'System.Windows.Forms', 'System.Drawing']

#- Requires node-clr v0.0.18+ to work correctly.
Δimport System.Windows
Δimport System.Windows.Input
Δimport System.Windows.Media

#.{ [Classes]
Δexport class XamlWindow
	# --Methods goes here.
	constructor: (markup) ->
		@form = Markup.XamlReader.Parse(markup)

	destroy: () ->
		@form.Dispose()

	find_child: (id) ->
		@form.FindName id

	find_res: (id) ->
		@form.FindResource id

	center: () ->
		@x = (SystemParameters.PrimaryScreenWidth  - @width)  / 2
		@y = (SystemParameters.PrimaryScreenHeight - @height) / 2

	show: (modal = true) ->
		if modal then @form.ShowDialog() else @form.Show()

	request_file: (filter = 'All Files|*.*', mod) ->
		dlg	= 
			if mod is 'save' then	new Microsoft.Win32.SaveFileDialog
			else					new Microsoft.Win32.OpenFileDialog
		dlg.Multiselect	= true if mod is 'multi'
		dlg.Filter		= filter
		if dlg.ShowDialog @form then return if dlg.Multiselect then repack dlg.FileNames else dlg.FileName

	request_text: (prompt, title = @title, responce = '') ->
		Microsoft.VisualBasic.Interaction.InputBox prompt, title, responce, -1, -1

	bind_key: (key, proc, mod = 'None', cmd = new RoutedCommand) ->
		key = Key[key]			if typeof key is 'string'
		mod = ModifierKeys[mod]	if typeof mod is 'string'
		@form.InputBindings.Add new KeyBinding cmd, key, mod
		if proc? then @form.CommandBindings.Add new CommandBinding(cmd, proc)

	# --Getters/setters.
	@getter 'title', ()			-> @form.Title
	@setter 'title', (val)		-> @form.Title = val
	@getter 'x', ()				-> @form.Left
	@setter 'x', (val)			-> @form.Left = val
	@getter 'y', ()				-> @form.Top
	@setter 'y', (val)			-> @form.Top = val
	@getter 'width', ()			-> @form.Width
	@setter 'width', (val)		-> @form.Width = val
	@getter 'height', ()		-> @form.Height
	@setter 'height', (val)		-> @form.Height = val
	@getter 'icon', ()			-> @form.Icon
	@setter 'icon', ()			-> @form.Icon = val
	@getter 'state', ()			-> @form.WindowState
	@setter 'state', (val)		-> @form.WindowState = val
# -------------------- #
Δexport class PlayerWindow extends XamlWindow
	# --Methods goes here.
	constructor: () ->
		# Initial setup.
		super System.IO.File.ReadAllText "../assets/player.xaml"
		@player			= new MusicBox("C:/Users/Guevara-chan/Downloads/via-gra-kto-ty-mne_(mp3.cc).mp3")
		@[id.name[1..]]	= new id(@) for id in [Δtime, Δbuttons, Δplaylist, Δvolume, Δtray]
		@center()
		self = @
		# Window eventing.
		@form.StateChanged.add	@on.collapse
		# Player eventing.
		@player.on 'pulse',			-> self.time.sync()
		@player.on 'play_signal',	-> self.playlist.sync()
		@player.on 'jam', (msg)		-> self.fault msg
		# Finalization.
		@show true
		@destroy()

	destroy: () ->
		@player.destroy()
		@tray.visible		= false
		@form.Visibility	= Visibility.Hidden

	fault: (msg) ->
		if msg instanceof Error then msg = msg.stack
		console.log msg
		MessageBox.Show(msg, "⬛⬛[Error encountered]⬛⬛", MessageBoxButton.OK, MessageBoxImage.Error)

	flick: (show_on = not @form.ShowInTaskbar) ->
		@form.ShowInTaskbar	= show_on
		@tray.visible		= not show_on
		@state				= if show_on then WindowState.Normal else WindowState.Minimized

	@new_branch 'on',
		collapse: ()	-> @flick @visible

	@getter 'visible', ()	-> not @state.Equals(WindowState.Minimized)

	# --Buttons protobranch.
	class Δbuttons
		constructor: (host) ->
			# Initial setup.
			Object.setPrototypeOf (Object.getPrototypeOf @), host
			@ui = 
				styles:
					off:	@find_res 'round_button_switch'
					on:		@find_res 'round_button'
			# Layout reparsing:
			for id, index in ['add', 'import', 'export', 'clear', 'switch', 'prev', 'next', 'shuffler', 'repeater']
				(@ui[id] = @find_child "btn_#{id}").Click.add @on[id]
				if hotkey = ['A', 'I', 'E', 'Delete', '', 'P', 'N', 'S', 'R'][index]
					@bind_key hotkey, @on[id], 'Control'
			# Finalization.
			@bind_key 'Space', @on.switch # Space -> play.
			@sync()

		sync: () ->
			iif = (bool, val_true = "Disable", val_false = "Enable") -> if bool then val_true else val_false
			[@ui.switch.Content	, @ui.switch.ToolTip]	= iif @playing, ["❚❚", "Halt [Space]"], ["▶", "Play [Space]"]
			[@ui.shuffler.Style	, @ui.shuffler.ToolTip]	=
				[@ui.styles[iif @shuffle, 'on', 'off'], "#{iif @shuffle} shuffle play [Ctrl+S]"]
			[@ui.repeater.Style	, @ui.repeater.ToolTip]	=
				[@ui.styles[iif @repeat, 'on', 'off'], "#{iif @repeat} repeat mode [Ctrl+R]"]
			return @

		@new_branch 'on',
			add:		() -> @playlist.add(); 			@
			import:		() -> @playlist.import();		@
			export:		() -> @playlist.export();		@
			clear:		() -> @playlist.clear();		@
			prev:		() -> @playlist.step(true);		@
			next:		() -> @playlist.step();			@
			switch:		() -> @playing	= not @playing;	@
			shuffler:	() -> @shuffle	= not @shuffle;	@
			repeater: 	() -> @repeat	= not @repeat; 	@

		@getter 'shuffle', ()		-> @player.random
		@setter 'shuffle', (val)	-> @player.random = val; @sync()
		@getter 'repeat', ()		-> @player.loop
		@setter 'repeat', (val)		-> @player.loop = val; @sync()
		@getter 'playing', ()		-> @player.is_on
		@setter 'playing', (val)	-> @player.switch val; @sync()

	# --Playlist protobranch.
	class Δplaylist
		constructor: (host) ->
			Object.setPrototypeOf (Object.getPrototypeOf @), host
			@ui	= {view: @find_child "playlist", }
			@ui.view.SelectionChanged.add @on.change
			@sync()

		sync: () ->
			# Auxilary refill procedure.
			new_entry = (title, length) =>
				item = new Controls.ListViewItem()
				item.PreviewMouseRightButtonDown.add @on.context
				item.Content =
					idx:	@ui.view.Items.Count + 1 + "⋮"
					title:	title
					len:	(if length then "⋮#{length.ToString 'm\\:ss'}" else "OH MY GOD")
				@listing.Add item
			# Actual list setup.
			@listing.Clear()
			new_entry(track.title, track.length) for track in @player.kiosk
			@ui.view.SelectedIndex = @selected
			# Finalization.
			return @

		add: (sources = @request_file @res.audio_formats, 'multi') ->
			@player.load sources if sources
			@sync()

		import: (sources = @request_file @res.list_formats, 'multi') ->
			@sync()

		export: (dest = @request_file @res.list_formats, 'save') ->
			@sync()

		clear: () ->
			@player.empty()
			@sync()

		step: (backwards) ->
			@selected = (@selected + if backwards then -1 else 1) % @length

		select: (idx = 0) ->
			if idx isnt @selected
				@player.repertory.selected = idx
				@ui.view.SelectedIndex = @selected
				if @buttons.playing then @player.play() else @player.stop()
				@time.sync()
			return @

		show_menu: (idx = selected) ->


		@new_branch 'on',
			context:	(src, e) -> e.Handled = true; @
			change:		(src, e) -> @select @ui.view.SelectedIndex if @ui.view.SelectedIndex isnt -1

		@getter 'listing', ()		-> @ui.view.Items
		@getter 'length', ()		-> @listing.Count
		@getter 'is_empty',	()		-> @length is 0
		@getter 'selected_item', ()	-> @listing.get(@selected) if @selected >= 0
		@getter 'selected', ()		-> @player.repertory.selected
		@setter 'selected', (val)	-> @select(val)

	# --Timeline protobranch.
	class Δtime
		constructor: (host) ->
			# Initial setup.
			Object.setPrototypeOf (Object.getPrototypeOf @), host
			@ui = {}
			for id in ['line', 'played', 'remains']
				@ui[id] = @find_child "time_#{id}"
			# Event handling.
			@ui.line.MouseLeftButtonDown.add @on.change
			@ui.line.MouseMove.add (src, e) => @on.change(src, e) if e.LeftButton.Equals(MouseButtonState.Pressed)
			# Finalization.
			@sync()

		sync: () ->
			[@ui.played.Content, @ui.remains.Content] =
				for span in [@played, @remains]
					if span					then "￭「#{span.ToString 'm\\:ss'}」￭"
					else if @now_playing	then "￭「?:?」￭"
					else "⏹|⏹"
			@ui.line.Maximum	= if @total		then @total.TotalSeconds	else 0
			@ui.line.Value		= if @played	then @played.TotalSeconds	else 0
			return @

		@new_branch 'on',
			change:	(src, e)		-> @progress = e.GetPosition(src).X / src.ActualWidth * 100; @

		@getter 'remains', ()		-> @total?.Subtract(@played)
		@getter 'total', ()			-> @player.cache?.length
		@getter 'played', ()		-> @player.cache?.position
		@setter 'played', (val)		-> @player.cache?.position = val; @sync()
		@getter 'progress', ()		-> @player.cache?.progress
		@setter 'progress', (val)	-> @player.cache?.rewind val; @sync()

	# --Volume protobranch.
	class Δvolume
		constructor: (host) ->
			# Initial setup.
			Object.setPrototypeOf (Object.getPrototypeOf @), host
			@ui =
				styles:
					off:	@find_res 'ghost_button_red'	
					on:		@find_res 'ghost_button'
			# Layout reparsing:		
			for id in ['bar', 'symbol']
				@ui[id]	= @find_child "vol_#{id}"
			@ui.bar.ValueChanged.add	@on.change
			@ui.symbol.Click.add		@on.switcher
			@bind_key 'V', @on.switcher, 'Control'
			# Finalization.
			@sync()

		sync: () ->
			@ui.bar.Value = @level
			[@ui.bar.ToolTip, @ui.symbol.ToolTip, @ui.symbol.Content, @ui.symbol.Style, @ui.symbol.Margin] =
			if @is_muted
						["Muted", "Enable sound [Ctrl+V]", "🔇", @ui.styles.off, new Thickness -1]
				else	["Volume = #{@level.toFixed(1)}%", "Mute [Ctrl+V]", "🔊", @ui.styles.on
						new Thickness 1, -3, 1, -3]
			return @

		switch: (turn_on = @is_muted) ->
			@level = if turn_on then 100 else 0
			return @

		@new_branch 'on',
			change:		() -> @level = @ui.bar.Value;	@
			switcher:	() -> @switch();				@

		@getter 'is_muted', ()	-> @level is 0
		@getter 'level', ()		-> @player.volume * 100
		@setter 'level', (val)	-> @player.volume = val / 100; @sync()

	# --Tray icon protobranch.
	class Δtray
		constructor: (host) ->
			# Auxilary function.
			menu_item = (label = "-", handler) =>
				item		= new wf.MenuItem
				item.Text	= label
				item.Click.add(handler) if handler
				return item
			# Initial setup.
			Object.setPrototypeOf (Object.getPrototypeOf @), host
			@ui			= notifier: new wf.NotifyIcon(), items: {delim: () -> menu_item()}
			@message	= '•Vy:nil•\n-Left click to restore.\n-Right click for menu.'
			@icon		=
				if @icon then @icon
				else System.Drawing.Icon.ExtractAssociatedIcon wf.Application.ExecutablePath
			@ui.notifier.ContextMenu = new wf.ContextMenu
			# Event handling.
			@ui.notifier.MouseClick.add @on.restore
			@ui.notifier.MouseDown.add @on.update
			# Menu pre-caching:
			@ui.items[id] = menu_item(label, @on[id]) for [label, id] in [
				["Terminate",	'terminate']
				["I.Am.Error",	'switch']
				["Next track",	'next']
				["Prev track",	'prev']
			]

		sync: () ->
			# Primary menu building.
			@ui.notifier.ContextMenu.MenuItems.Clear()
			@ui.notifier.ContextMenu.MenuItems.Add item for item in [
				@ui.items.switch
				@ui.items.delim()
				@ui.items.prev
				@ui.items.next
				@ui.items.delim()
				@ui.items.terminate
			]
			# Additional menu setup.
			@ui.items.switch.Text = if @buttons.playing then "Halt" else "Play"
			return @

		@new_branch 'on',
			update:		(src, e) -> @sync();											@
			restore:	(src, e) -> @flick(on) if e.Button.Equals wf.MouseButtons.Left;	@
			switch:		(src, e) -> @buttons.on.switch();								@
			next:		(src, e) -> @buttons.on.next();									@
			prev:		(src, e) -> @buttons.on.prev();									@
			terminate:	(src, e) -> @destroy();											@

		wf = System.Windows.Forms

		@getter 'icon', ()			-> @ui.notifier.Icon
		@setter 'icon', (val)		-> @ui.notifier.Icon = val
		@getter 'message', ()		-> @ui.notifier.Text
		@setter 'message', (val)	-> @ui.notifier.Text = val
		@getter 'visible', ()		-> @ui.notifier.Visible
		@setter 'visible', (val)	-> @ui.notifier.Visible = val

	# --Embedded resources.
	@getter 'res', ->
		audio_formats: "MPEG-1/2/2.5 Layer 3 (*.mp3)|*.mp3|Waveform Audio File Format (*.wav)|*.wav|
		Windows Media Audio (*.wma)|*.wma|Dolby Digital (*.ac3)|*.ac3|Advanced Audio Codings (*.aac)|*.aac|
		Free Lossless Audio Codec (*.flac)|(*.flac)|Ogg Vorbis (*.ogg)|*.ogg|All Files|*.*"
		list_formats: "Vy:nil listing (*.nil)|*.nil|All Files|*.*"
#.}

# ==Additional fixes==
global.setInterval = (proc, time) ->
	timer = new Threading.DispatcherTimer()
	timer.Interval = System.TimeSpan.FromMilliseconds time
	timer.Tick.add proc
	timer.Start()

global.setTimeout = (proc, time) ->
	setInterval ((src) -> proc(); src.Stop()), time

# ==Main code==
new PlayerWindow()