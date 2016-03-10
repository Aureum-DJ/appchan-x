QR.post = class
  constructor: (select) ->
    el = $.el 'a',
      className: 'qr-preview'
      draggable: true
      href: 'javascript:;'
    $.extend el, <%= html('<a class="remove fa" title="Remove">\uf057</a><label hidden><input type="checkbox"> Spoiler</label><span></span>') %>

    @nodes =
      el:      el
      rm:      el.firstChild
      label:   $ 'label', el
      spoiler: $ 'input', el
      span:    el.lastChild

    $.on el,             'click',  @select
    $.on @nodes.rm,      'click',  (e) => e.stopPropagation(); @rm()
    $.on @nodes.label,   'click',  (e) => e.stopPropagation()
    $.on @nodes.spoiler, 'change', (e) =>
      @spoiler = e.target.checked
      QR.nodes.spoiler.checked = @spoiler if @ is QR.selected
    $.add QR.nodes.dumpList, el

    for event in ['dragStart', 'dragEnter', 'dragLeave', 'dragOver', 'dragEnd', 'drop']
      $.on el, event.toLowerCase(), @[event]

    @thread = if g.VIEW is 'thread'
      g.THREADID
    else
      'new'

    prev = QR.posts[QR.posts.length - 1]
    QR.posts.push @
    @nodes.spoiler.checked = @spoiler = if prev and Conf['Remember Spoiler']
      prev.spoiler
    else
      false
    QR.persona.get (persona) =>
      @name = if 'name' of QR.persona.always
        QR.persona.always.name
      else if prev
        prev.name
      else
        persona.name

      @email = if 'email' of QR.persona.always
        QR.persona.always.email
      else if prev and !/^sage$/.test prev.email
        prev.email
      else
        persona.email

      @sub = if 'sub' of QR.persona.always
        QR.persona.always.sub
      else
        ''

      if QR.nodes.flag
        @flag = if prev
          prev.flag
        else
          persona.flag
      @load() if QR.selected is @ # load persona
    @select() if select
    @unlock()
    # Post count temporarily off by 1 when called from QR.post.rm
    $.queueTask -> QR.captcha.onNewPost()

  rm: ->
    @delete()
    index = QR.posts.indexOf @
    if QR.posts.length is 1
      new QR.post true
      $.rmClass QR.nodes.el, 'dump'
    else if @ is QR.selected
      (QR.posts[index-1] or QR.posts[index+1]).select()
    QR.posts.splice index, 1
    QR.status()

  delete: ->
    $.rm @nodes.el
    URL.revokeObjectURL @URL

  lock: (lock=true) ->
    @isLocked = lock
    return unless @ is QR.selected
    for name in ['thread', 'name', 'email', 'sub', 'com', 'fileButton', 'filename', 'spoiler', 'flag'] when node = QR.nodes[name]
      node.disabled = lock
    @nodes.rm.style.visibility = if lock then 'hidden' else ''
    (if lock then $.off else $.on) QR.nodes.filename.previousElementSibling, 'click', QR.openFileInput
    @nodes.spoiler.disabled = lock
    @nodes.el.draggable = !lock

  unlock: ->
    @lock false

  select: =>
    if QR.selected
      QR.selected.nodes.el.id = null
      QR.selected.forceSave()
    QR.selected = @
    @lock @isLocked
    @nodes.el.id = 'selected'
    # Scroll the list to center the focused post.
    rectEl   = @nodes.el.getBoundingClientRect()
    rectList = @nodes.el.parentNode.getBoundingClientRect()
    @nodes.el.parentNode.scrollLeft += rectEl.left + rectEl.width/2 - rectList.left - rectList.width/2
    @load()

  load: ->
    # Load this post's values.

    for name in ['thread', 'name', 'email', 'sub', 'com', 'filename', 'flag']
      continue unless node = QR.nodes[name]
      node.value = @[name] or node.dataset.default or null

    QR.tripcodeHider.call QR.nodes['name']

    (if @thread isnt 'new' then $.addClass else $.rmClass) QR.nodes.el, 'reply-to-thread'

    @showFileData()
    QR.characterCount()

  save: (input) ->
    if input.type is 'checkbox'
      @spoiler = input.checked
      return
    {name}  = input.dataset
    @[name] = input.value or input.dataset.default or null
    switch name
      when 'thread'
        (if @thread isnt 'new' then $.addClass else $.rmClass) QR.nodes.el, 'reply-to-thread'
        QR.status()
        @updateFlashURL()
      when 'com'
        @nodes.span.textContent = @com
        QR.captcha.onPostChange()
        QR.characterCount()
        # Disable auto-posting if you're typing in the first post
        # during the last 5 seconds of the cooldown.
        if QR.cooldown.auto and @ is QR.posts[0] and 0 < QR.cooldown.seconds <= 5
          QR.cooldown.auto = false
      when 'filename'
        return unless @file
        @file.newName = @filename.replace /[/\\]/g, '-'
        unless /\.(jpe?g|png|gif|pdf|swf|webm)$/i.test @filename
          # 4chan will truncate the filename if it has no extension,
          # but it will always replace the extension by the correct one,
          # so we suffix it with '.jpg' when needed.
          @file.newName += '.jpg'
        @updateFilename()
        @updateFlashURL()

  forceSave: ->
    return unless @ is QR.selected
    # Do this in case people use extensions
    # that do not trigger the `input` event.
    for name in ['thread', 'name', 'email', 'sub', 'com', 'filename', 'spoiler', 'flag']
      continue unless node = QR.nodes[name]
      @save node
    return

  setComment: (com) ->
    @com = com or null
    if @ is QR.selected
      QR.nodes.com.value = @com

  setFile: (@file) ->
    @filename = file.name
    @filesize = $.bytesToString file.size
    @nodes.label.hidden = false if QR.spoiler
    QR.captcha.onPostChange()
    URL.revokeObjectURL @URL
    if @ is QR.selected
      @showFileData()
    else
      @updateFilename()
    @updateFlashURL()
    unless /^(image|video)\//.test file.type
      @nodes.el.style.backgroundImage = null
      return
    @setThumbnail()

  setThumbnail: ->
    # Create a redimensioned thumbnail.
    isVideo = /^video\//.test @file.type
    el = $.el (if isVideo then 'video' else 'img')

    $.on el, (if isVideo then 'loadeddata' else 'load'), =>
      # Verify element dimensions.
      errors = @checkDimensions el, isVideo
      if errors.length
        QR.error error for error in errors
        @URL = fileURL # this.removeFile will revoke this proper.
        return if (QR.posts.length is 1) or (@com and @com.length) then @rmFile() else @rm() # I wrote this while listening to MCR

      # Generate thumbnails only if they're really big.
      # Resized pictures through canvases look like ass,
      # so we generate thumbnails `s` times bigger then expected
      # to avoid crappy resized quality.
      s = 90 * 2 * window.devicePixelRatio
      s *= 3 if @file.type is 'image/gif' # let them animate

      if isVideo
        height = el.videoHeight
        width  = el.videoWidth
      else
        {height, width} = el
        if height < s or width < s
          @URL = fileURL
          @nodes.el.style.backgroundImage = "url(#{@URL})"
          return

      if height <= width
        width  = s / height * width
        height = s
      else
        height = s / width  * height
        width  = s

      cv = $.el 'canvas'
      cv.height = el.height = height
      cv.width  = el.width  = width
      cv.getContext('2d').drawImage el, 0, 0, width, height
      URL.revokeObjectURL fileURL
      cv.toBlob (blob) =>
        @URL = URL.createObjectURL blob
        @nodes.el.style.backgroundImage = "url(#{@URL})"

    fileURL = URL.createObjectURL @file
    el.src = fileURL

  checkDimensions: (el, video) ->
    err = []
    if video
      {videoHeight, videoWidth, duration} = el
      max_height = if QR.max_height < QR.max_height_video
        QR.max_height
      else
        QR.max_height_video
      max_width = if QR.max_width  < QR.max_width_video
        QR.max_width
      else
        QR.max_width_video
      if videoHeight > max_height or videoWidth > max_width
        err.push "#{@file.name}: Video too large (video: #{videoHeight}x#{videoWidth}px, max: #{max_height}x#{max_width}px)"
      if videoHeight < QR.min_height or videoWidth < QR.min_width
        err.push "#{@file.name}: Video too small (video: #{videoHeight}x#{videoWidth}px, min: #{QR.min_height}x#{QR.min_width}px)"
      unless isFinite el.duration
        err.push "#{file.name}: Video lacks duration metadata (try remuxing)"
      if g.BOARD.ID is 'wsg' or g.BOARD.ID is 'gif'
        if duration > QR.max_duration_video_alt
          err.push "#{@file.name}: Video too long (video: #{duration}s, max: #{QR.max_duration_video_alt}s)"
      else
        if duration > QR.max_duration_video
          err.push "#{@file.name}: Video too long (video: #{duration}s, max: #{QR.max_duration_video}s)"
      <% if (type === 'userscript') { %>
      if el.mozHasAudio
        err.push "#{file.name}: Audio not allowed"
      <% } %>
    else
      {height, width} = el
      if height > QR.max_height or width > QR.max_width
        err.push "#{@file.name}: Image too large (image: #{height}x#{width}px, max: #{QR.max_height}x#{QR.max_width}px)"
      if height < QR.min_height or width < QR.min_width
        err.push "#{@file.name}: Image too small (image: #{height}x#{width}px, min: #{QR.min_height}x#{QR.min_width}px)"
    err

  rmFile: ->
    return if @isLocked
    delete @file
    delete @filename
    delete @filesize
    @nodes.el.title = null
    QR.nodes.fileContainer.title = ''
    @nodes.el.style.backgroundImage = null
    @nodes.label.hidden = true if QR.spoiler
    @showFileData()
    @updateFlashURL()
    URL.revokeObjectURL @URL

  updateFilename: ->
    long = "#{@filename} (#{@filesize})\nCtrl/\u2318+click to edit filename. Shift+click to clear."
    @nodes.el.title = long
    return unless @ is QR.selected
    QR.nodes.fileContainer.title = long

  showFileData: ->
    if @file
      @updateFilename()
      QR.nodes.filename.value       = @filename
      QR.nodes.spoiler.checked      = @spoiler
      $.addClass QR.nodes.fileSubmit, 'has-file'
    else
      $.rmClass QR.nodes.fileSubmit, 'has-file'

  updateFlashURL: ->
    return unless g.BOARD.ID is 'f'
    if @thread is 'new' or !@file
      url = ''
    else
      url = @filename
      url = url.replace(/"/g, '%22') if $.engine in ['blink', 'webkit']
      url = url
        .replace(/[\t\n\f\r \xa0\u200B\u2029\u3000]+/g, ' ')
        .replace(/(^ | $)/g, '')
        .replace(/\.[0-9A-Za-z]+$/, '')
      url = "https://i.4cdn.org/f/#{encodeURIComponent E url}.swf\n"
      oldURL = @flashURL or ''
      if url isnt oldURL
        com = @com or ''
        if com[...oldURL.length] is oldURL
          @setComment url + com[oldURL.length..]
        @flashURL = url

  pasteText: (file) ->
    reader = new FileReader()
    reader.onload = (e) =>
      text = e.target.result
      if @com
        @com += "\n#{text}"
      else
        @com = text
      if QR.selected is @
        QR.nodes.com.value    = @com
      @nodes.span.textContent = @com
    reader.readAsText file

  dragStart: (e) ->
    e.dataTransfer.setDragImage @, e.layerX, e.layerY
    $.addClass @, 'drag'
  dragEnd:   -> $.rmClass  @, 'drag'
  dragEnter: -> $.addClass @, 'over'
  dragLeave: -> $.rmClass  @, 'over'

  dragOver: (e) ->
    e.preventDefault()
    e.dataTransfer.dropEffect = 'move'

  drop: ->
    $.rmClass @, 'over'
    return unless @draggable
    el       = $ '.drag', @parentNode
    index    = (el) -> [el.parentNode.children...].indexOf el
    oldIndex = index el
    newIndex = index @
    (if oldIndex < newIndex then $.after else $.before) @, el
    post = QR.posts.splice(oldIndex, 1)[0]
    QR.posts.splice newIndex, 0, post
    QR.status()
