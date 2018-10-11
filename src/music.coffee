EventEmitter		= require('events')
{Δimport, Δexport}	= require('./util.coffee')
require('clr').init {assemblies: ['../bin/CSCore.dll', 'System', 'mscorlib']}

#- Requires CSCore v.1.2.0+ (https://github.com/filoe/cscore)
Δimport CSCore
Δimport CSCore.Codecs
Δimport CSCore.SoundOut
Δimport CSCore.Tags.ID3

#.{ [Classes]
Δexport class Record
	# --Methods goes here.
	constructor: (@origin) ->
		if @origin instanceof Record then @origin.destroy(); @origin = @origin.origin
		@origin = normalize_path @origin
		@audio  = Record.load_audio(@origin)
		@meta	= Object.assign Record.guess_title(@origin, @is_finite), (try Record.extract_metadata @origin)
		@kiosk	= title: @title, length: @length
		Object.freeze @

	destroy: () ->
		@audio.Dispose()

	rewind: (progress = 0) ->
		if @can_rewind
			if progress.GetType?().Equals(System.TimeSpan)
				Extensions.SetPosition(@audio, progress)
			else if @is_finite or not progress
				@offset = @audio.Length * progress // 100
			else throw new Error('unable to find position in infinite record')
		return @

	normalize_path = (path) ->
		if typeof path is 'string' then new System.Uri path else path

	@load_audio: (origin) ->
		# Service objects preparation.
		origin = normalize_path origin
		# Consumption phase:
		if origin.IsFile
			return CodecFactory.Instance.GetCodec origin
		else
			return new MP3.Mp3WebStream origin

	@extract_metadata: (origin) ->
		# Service objects preparation.
		streamer	= new System.Net.WebClient()
		stream		= streamer.OpenRead origin
		# Actual metadata extraction (ID3).
		if id3 = [ID3v2.FromStream(stream)?.QuickInfo, stream.Close(), streamer.Dispose()][0]
			{
				title:	id3.Title;		album: id3.Album;	artist: id3.Artist;	lead_performers: id3.LeadPerformers
				comments: id3.Comments;	image: id3.Image;	year: id3.Year;		track_number: id3.TrackNumber
				original_release: id3.OriginalReleaseYear;	genre: id3.Genre
			}

	@guess_title: (origin, finity = true) ->
		# Service objects preparation.
		origin = normalize_path origin
		# Guessing switch.
		unless finity								# (infinite stream -> probably an internet radio)
			guess:	"/" + [origin.Host
				":" + origin.Port	if origin.Port		isnt -1
				origin.LocalPath	if origin.LocalPath	isnt '/'].filter(Boolean).join('') + "/"
			heur:	'stream'
		else if (local = origin.LocalPath) isnt '/'	# (localizable path -> probably remote file)
			guess:	System.IO.Path.GetFileNameWithoutExtension local
			heur:	'file'
		else										# (unable to to determine source -> no guesses)
			guess:	origin.ToString()
			heur:	"???"

	@describe: (data) ->
		if data instanceof Record then data.kiosk else title: Record.guess_title(data).guess

	# --Getters/setters.
	@getter 'position',		-> Extensions.GetPosition(@audio)
	@getter 'length',		-> Extensions.GetLength(@audio)				if @is_finite
	@getter 'progress',		-> @audio.Position / @audio.Length * 100	if @is_finite
	@getter 'title',		-> if @meta.title	then @meta.title			else @meta.guess
	@getter 'is_finished',	-> if @is_finite	then @position is @length	else false
	@getter 'is_finite',	-> @audio.Length > 0
	@getter 'can_rewind',	-> @audio.CanSeek
	@getter 'offset',		-> @audio.Position
	@setter 'offset',		(val) -> @audio.Position = val
# -------------------- #
Δexport class PlayList
	# --Methods goes here.
	constructor: (initial_list) ->
		@listing = []
		@merge initial_list
		Object.freeze @

	destroy: () ->
		@clear()

	move: (src_idx = @selected, dest_idx = 0) ->
		if src_idx isnt dest_idx
			@check_index dest_idx, 1
			if @selected is src_idx			then @selected = dest_idx
			else if dest_idx <= @selected	then @selected = @selected + 1
			@listing.splice dest_dix, 0, @remove(src_idx)

	add: (source, dest_idx = @length) ->
		@listing.push {Δ: source}
		@move @length-1, dest_idx

	merge: (source_list) ->
		if source_list instanceof PlayList		then source_list = source_list.checkout()
		else unless Array.isArray source_list	then source_list = [source_list]
		@add(src) for src in source_list

	remove: (idx = @length-1) ->
		@check_index idx
		if idx <= @selected then @selected = Math.max(@selected - 1, 0)
		return @listing.splice(idx, 1)

	clear: () ->
		@remove() while not @is_empty

	sublink: (data, channel = '', idx = @selected) ->
		@check_index idx
		@listing[idx]["Δ#{channel}"] = data

	request: (idx = @selected, channel = '') ->
		@check_index idx
		@listing[idx]["Δ#{channel}"]

	probe: (idx, channel) ->
		if data = @request idx, channel then data else @request idx

	next: (shuffle = false) ->
		@selected =
			if shuffle then	Math.random() * @length // 1
			else			(@selected+1) % @length

	check_index: (idx, edge = 0) ->
		if idx < 0					then throw new Error "playlist index underflow"
		if idx >= @length + edge	then throw new Error "playlist index overflow"

	# --Accumulators.
	Δselected = 0

	# --Getters/setters.
	@getter 'length',	-> @listing.length
	@getter 'is_empty',	-> @length is 0
	@getter 'checkout', -> @listing[..]
	@getter 'selected',	-> Δselected
	@setter 'selected',	(val) -> @check_index val; Δselected = val
# -------------------- #
Δexport class MusicBox extends EventEmitter
	# --Methods goes here.
	constructor: (source_list, @random = false, @pulse_interval = 1000, @emitter = true) ->
		super()
		@output		= new WasapiOut()
		@repertory	= new PlayList()
		@load source_list, true
		setInterval @tick.bind(@), 500

	destroy: () ->
		@empty().output.Dispose()
		
	load: (source_list, refit) ->
		@empty() if refit
		@repertory.merge source_list
		return @

	eject: (record_id = @repertory.current) ->
		if @cache is @repertory.request record_id, 'cache' then @stop()
		@repertory.remove(record_id)
		return @

	empty: () ->
		@stop().state = 'setup'
		@repertory.clear()
		return @

	rewind: (progress = 0) ->
		@cache.rewind progress
		return @

	next: () ->
		@signal 'next_signal', if @loop then @repertory.selected else @repertory.next(@random)
		if @is_on then @play() else @stop()
		return @

	play: (src = @repertory.selected) ->
		# Necessary preparations.
		@stop().state = 'playing'
		if typeof src is 'number' then src = @repertory.request(list_idx = src)
		# Actual playing procedures.
		@cache = new Record src
		if list_idx? then @repertory.sublink @cache, 'cache', list_idx		
		@output.Initialize(@cache.audio)
		@output.Play()
		# Event emitters.
		@signal 'play_signal', @now_playing, list_idx
		@emit_pulse() if @pulse_interval 
		return @

	stop: () ->
		@cache?.destroy()
		try @output.Stop()
		@state = 'halt'
		@cache = 0[@signal "stop_signal", @cache]
		return @

	switch: (turn_on = @state isnt 'playing') ->
		# Necessary check.
		if @is_empty then @state = 'setup'; throw new Error "no records to setup playback"
		# State-machine switching.
		switch @state
			when 'playing' 	then (@output.Pause(); @state = 'paused')	unless turn_on
			when 'paused'	then (@output.Resume(); @state = 'playing')	if turn_on
			when 'idle'		then @stop()								unless turn_on
			when 'halt', 'setup' then if turn_on
				if @state = 'setup' and @random then @next()
				@state = 'idle'
		return @

	signal: (id, args...) ->
		@emit id, args... if @emitter

	emit_pulse: () ->
		if status = @now_playing
			@signal 'pulse', status
			setTimeout @emit_pulse.bind(@), @pulse_interval
		return @

	tick: () ->
		try
			if @now_playing
				@output.Volume = Δvolume
			else if @is_on
				if not @is_empty
					if @state is 'playing' then @next() else @play()
				else @stop()
		catch error
			@stop().signal 'jam', error
		return @

	# --Accumulators.
	Δstate	= '[I am error]'
	Δcache	= undefined
	Δvolume	= 1

	# --Getters/setters.
	@getter	'now_playing',	-> @cache unless @output.PlaybackState.Equals(PlaybackState.Stopped)
	@getter 'kiosk', 		-> Record.describe @repertory.probe idx, 'cache' for idx in [0...@repertory.length]
	@getter 'is_empty',		-> @repertory.is_empty
	@getter 'is_on',		-> @state in ['playing', 'idle']
	@getter 'volume',		-> Δvolume
	@setter 'volume',		(val) -> Δvolume = val
	@getter 'state',		-> Δstate
	@setter 'state',		(val) -> Δstate = val; @signal 'state_switch', val
	@getter 'cache',		-> Δcache
	@setter 'cache',		(val) -> Δcache = val; @signal 'cache_switch', val
#.}