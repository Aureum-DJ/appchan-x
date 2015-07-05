QR =
  mimeTypes: ['image/jpeg', 'image/png', 'image/gif', 'application/pdf', 'application/vnd.adobe.flash.movie', 'application/x-shockwave-flash', 'video/webm']

  init: ->
    @db = new DataBoard 'yourPosts'
    @posts = []

    return if g.VIEW is 'archive'

    $.globalEval 'document.documentElement.dataset.jsEnabled = true;'
    noscript = Conf['Force Noscript Captcha'] or !doc.dataset.jsEnabled
    @captcha = Captcha[if noscript then 'noscript' else 'v2']

    $.on d, '4chanXInitFinished', @initReady

    window.addEventListener 'focus', @focus, true
    window.addEventListener 'blur',  @focus, true
    # We don't receive blur events from captcha iframe.
    $.on d, 'click', @focus

    Post.callbacks.push
      name: 'Quick Reply'
      cb:   @node

    return unless Conf['Header Shortcut'] or Conf['Page Shortcut']

    sc = $.el 'a',
      className: "qr-shortcut fa #{unless Conf['Persistent QR'] then 'disabled' else ''}"
      textContent: '\uf075'
      title: 'Quick Reply'
      href: 'javascript:;'

    $.on sc, 'click', ->
      if !QR.nodes or QR.nodes.el.hidden
        $.event 'CloseMenu'
        QR.open()
        QR.nodes.com.focus()
      else
        QR.close()
      $.toggleClass @, 'disabled'

    return Header.addShortcut sc, true if Conf['Header Shortcut']

    $.addClass sc, 'on-page'
    $.rmClass  sc, 'fa'
    sc.textContent = if g.VIEW is 'thread' then 'Reply to Thread' else 'Start a Thread'
    con = $.el 'div',
      className: 'center'
    $.add con, sc
    $.asap (-> d.body), ->
      $.asap (-> $.id 'postForm'), ->
        $.before $.id('postForm'), con

  initReady: ->
    $.off d, '4chanXInitFinished', @initReady
    QR.postingIsEnabled = !!$.id 'postForm'
    return unless QR.postingIsEnabled

    $.on d, 'paste',              QR.paste
    $.on d, 'dragover',           QR.dragOver
    $.on d, 'drop',               QR.dropFile
    $.on d, 'dragstart dragend',  QR.drag

    # We can thread update and index refresh without loading a new page, so...
    $.on d, 'IndexRefresh', QR.generatePostableThreadsList
    $.on d, 'ThreadUpdate', QR.statusCheck

    return if !Conf['Persistent QR']
    QR.open()
    QR.hide() if Conf['Auto Hide QR']

  statusCheck: ->
    return unless QR.nodes
    {thread} = QR.posts[0]
    if thread isnt 'new' and g.threads["#{g.BOARD}.#{thread}"].isDead
      QR.abort()
    else
      QR.status()

  node: ->
    if QR.db.get {boardID: @board.ID, threadID: @thread.ID, postID: @ID}
      $.addClass @nodes.root, 'your-post'
    $.on $('a[title="Reply to this post"]', @nodes.info), 'click', QR.quote

  persist: ->
    return unless QR.postingIsEnabled
    QR.open()
    QR.hide() if Conf['Auto Hide QR']

  open: ->
    if QR.nodes
      QR.captcha.setup() if QR.nodes.el.hidden
      QR.nodes.el.hidden = false
      QR.unhide()
      return
    try
      QR.dialog()
    catch err
      delete QR.nodes
      Main.handleErrors
        message: 'Quick Reply dialog creation crashed.'
        error: err

  close: ->
    if QR.req
      QR.abort()
      return
    QR.nodes.el.hidden = true
    QR.cleanNotifications()
    d.activeElement.blur()
    $.rmClass QR.nodes.el, 'dump'
    if Conf['QR Shortcut']
      $.toggleClass $('.qr-shortcut'), 'disabled'
    new QR.post true
    for post in QR.posts.splice 0, QR.posts.length - 1
      post.delete()
    QR.cooldown.auto = false
    QR.status()
    QR.captcha.destroy()

  focus: ->
    $.queueTask ->
      return unless QR.nodes
      unless $$('.goog-bubble-content > iframe').some((el) -> el.getBoundingClientRect().top >= 0)
        focus = d.activeElement and QR.nodes.el.contains(d.activeElement)
        $[if focus then 'addClass' else 'rmClass'] QR.nodes.el, 'focus'
      if chrome?
        # XXX Stop anomalous scrolling on space/tab in captcha iframe.
        if d.activeElement and QR.nodes.el.contains(d.activeElement) and d.activeElement.nodeName is 'IFRAME'
          QR.scrollY = window.scrollY
          $.on d, 'scroll', QR.scrollLock
        else
          $.off d, 'scroll', QR.scrollLock

  scrollLock: (e) ->
    if d.activeElement and QR.nodes.el.contains(d.activeElement) and d.activeElement.nodeName is 'IFRAME'
      window.scroll window.scrollX, QR.scrollY
    else
      $.off d, 'scroll', QR.scrollLock

  hide: ->
    d.activeElement.blur()
    $.addClass QR.nodes.el, 'autohide'
    QR.nodes.autohide.checked = true

  unhide: ->
    $.rmClass QR.nodes.el, 'autohide'
    QR.nodes.autohide.checked = false

  toggleHide: ->
    if @checked
      QR.hide()
    else
      QR.unhide()

  error: (err) ->
    QR.open()
    if typeof err is 'string'
      el = $.tn err
    else
      el = err
      el.removeAttribute 'style'
    if QR.captcha.isEnabled and /captcha|verification/i.test el.textContent
      QR.captcha.setup true
      QR.captcha.notify el
    else
      QR.notify el
    alert el.textContent if d.hidden

  notify: (el) ->
    notice = new Notice 'warning', el
    unless Header.areNotificationsEnabled and d.hidden
      QR.notifications.push notice
    else
      notif = new Notification el.textContent,
        body: el.textContent
        icon: Favicon.logo
      notif.onclick = -> window.focus()
      <% if (type === 'crx') { %>
      # Firefox automatically closes notifications
      # so we can't control the onclose properly.
      notif.onclose = -> notice.close()
      notif.onshow  = ->
        setTimeout ->
          notif.onclose = null
          notif.close()
        , 7 * $.SECOND
      <% } %>

  notifications: []

  cleanNotifications: ->
    for notification in QR.notifications
      notification.close()
    QR.notifications = []

  status: ->
    return unless QR.nodes
    {thread} = QR.posts[0]
    if thread isnt 'new' and g.threads["#{g.BOARD}.#{thread}"]?.isDead
      value    = 'Dead'
      disabled = true
      QR.cooldown.auto = false

    value = if QR.req
      QR.req.progress
    else
      QR.cooldown.seconds or value

    {status} = QR.nodes
    status.value = unless value
      'Submit'
    else if QR.cooldown.auto
      "Auto #{value}"
    else
      value
    status.disabled = disabled or false

  quote: (e) ->
    e?.preventDefault()
    return unless QR.postingIsEnabled

    sel  = d.getSelection()
    post = Get.postFromNode @
    text = if post.board.ID is g.BOARD.ID then ">>#{post}\n" else ">>>/#{post.board}/#{post}\n"
    if sel.toString().trim() and post is Get.postFromNode sel.anchorNode
      range = sel.getRangeAt 0
      frag  = range.cloneContents()
      ancestor = range.commonAncestorContainer
      # Quoting the insides of a spoiler/code tag.
      if $.x 'ancestor-or-self::*[self::s or contains(@class,"removed-spoiler")]', ancestor
        $.prepend frag, $.tn '[spoiler]'
        $.add     frag, $.tn '[/spoiler]'
      if insideCode = $.x 'ancestor-or-self::pre[contains(@class,"prettyprint")]', ancestor
        $.prepend frag, $.tn '[code]'
        $.add     frag, $.tn '[/code]'
      for node in $$ (if insideCode then 'br' else '.prettyprint br'), frag
        $.replace node, $.tn '\n'
      for node in $$ 'br', frag
        $.replace node, $.tn '\n>' unless node is frag.lastChild
      for node in $$ 's, .removed-spoiler', frag
        $.replace node, [$.tn('[spoiler]'), node.childNodes..., $.tn '[/spoiler]']
      for node in $$ '.prettyprint', frag
        $.replace node, [$.tn('[code]'), node.childNodes..., $.tn '[/code]']
      for node in $$ '.linkify[data-original]', frag
        $.replace node, $.tn node.dataset.original
      for node in $$ '.embedder', frag
        $.rm node.previousSibling if node.previousSibling?.nodeValue is ' '
        $.rm node
      text += ">#{frag.textContent.trim()}\n"

    QR.open()
    if QR.selected.isLocked
      index = QR.posts.indexOf QR.selected
      (QR.posts[index+1] or new QR.post()).select()
      $.addClass QR.nodes.el, 'dump'
      QR.cooldown.auto = true
    {com, thread} = QR.nodes
    thread.value = Get.threadFromNode @ unless com.value
    thread.nextElementSibling.firstElementChild.textContent = thread.options[thread.selectedIndex].textContent

    caretPos = com.selectionStart
    # Replace selection for text.
    com.value = com.value[...caretPos] + text + com.value[com.selectionEnd..]
    # Move the caret to the end of the new quote.
    range = caretPos + text.length
    com.setSelectionRange range, range
    com.focus()

    QR.selected.save com
    QR.selected.save thread

    $.rmClass $('.qr-shortcut'), 'disabled'

  characterCount: ->
    counter = QR.nodes.charCount
    count   = QR.nodes.com.textLength
    counter.textContent = count
    counter.hidden      = count < 1000
    (if count > 1500 then $.addClass else $.rmClass) counter, 'warning'

  drag: (e) ->
    # Let it drag anything from the page.
    toggle = if e.type is 'dragstart' then $.off else $.on
    toggle d, 'dragover', QR.dragOver
    toggle d, 'drop',     QR.dropFile

  dragOver: (e) ->
    e.preventDefault()
    e.dataTransfer.dropEffect = 'copy' # cursor feedback

  dropFile: (e) ->
    # Let it only handle files from the desktop.
    return unless e.dataTransfer.files.length
    e.preventDefault()
    QR.open()
    QR.handleFiles e.dataTransfer.files

  paste: (e) ->
    return unless e.clipboardData.items
    files = []
    for item in e.clipboardData.items when item.kind is 'file'
      blob = item.getAsFile()
      blob.name  = 'file'
      blob.name += '.' + blob.type.split('/')[1] if blob.type
      files.push blob
    return unless files.length
    QR.open()
    QR.handleFiles files
    $.addClass QR.nodes.el, 'dump'
  handleUrl:  ->
    url = prompt 'Enter a URL:'
    return if url is null
    CrossOrigin.file url, (blob) ->
      if blob
        QR.handleFiles([blob])
      else
        QR.error "Can't load image."

  handleFiles: (files) ->
    if @ isnt QR # file input
      files  = [@files...]
      @value = null
    return unless files.length
    QR.cleanNotifications()
    for file, i in files
      QR.handleFile file, i, files.length
    $.addClass QR.nodes.el, 'dump' unless files.length is 1

  handleFile: (file, index, nfiles) ->
    isSingle = nfiles is 1
    if /^text\//.test file.type
      if isSingle
        post = QR.selected
      else if index isnt 0 or (post = QR.posts[QR.posts.length - 1]).com
        post = new QR.post()
      post.pasteText file
      return
    unless file.type in QR.mimeTypes
      QR.error "#{file.name}: Unsupported file type."
      return
    max = QR.nodes.fileInput.max
    if /^video\//.test file.type
      if g.BOARD.ID is 'wsg' or g.BOARD.ID is 'gif'
      	max = Math.min(max, QR.max_size_video_alt)
      else
      	max = Math.min(max, QR.max_size_video)
    if file.size > max
      QR.error "#{file.name}: File too large (file: #{$.bytesToString file.size}, max: #{$.bytesToString max})."
      return
    if isSingle
      post = QR.selected
    else if (post = QR.posts[QR.posts.length - 1]).file
      post = new QR.post()
    post.setFile file

  openFileInput: (e) ->
    e.stopPropagation()
    if e.shiftKey and e.type is 'click'
      return QR.selected.rmFile()
    if (e.ctrlKey or e.metaKey) and e.type is 'click'
      $.addClass QR.nodes.filename, 'edit'
      QR.nodes.filename.focus()
    return if e.target.nodeName is 'INPUT' or (e.keyCode and e.keyCode not in [32, 13]) or e.ctrlKey
    e.preventDefault()
    QR.nodes.fileInput.click()

  generatePostableThreadsList: ->
    return unless QR.nodes
    list    = QR.nodes.thread
    options = [list.firstElementChild]
    for thread in g.BOARD.threads.keys
      options.push $.el 'option',
        value: thread
        textContent: "No.#{thread}"
    val = list.value
    $.rmAll list
    $.add list, options
    list.value = val
    return unless list.value
    # Fix the value if the option disappeared.
    list.value = if g.VIEW is 'thread'
      g.THREADID
    else
      'new'
    list.nextElementSibling.firstChild.textContent = list.options[list.selectedIndex].textContent if $.hasClass list, 'riced'

    (if g.VIEW is 'thread' then $.addClass else $.rmClass) QR.nodes.el, 'reply-to-thread'

  dialog: ->
    QR.nodes = nodes =
      el: dialog = UI.dialog 'qr', 'top:0;right:0;',
        <%= importHTML('Features/QuickReply') %>

    setNode = (name, query) ->
      nodes[name] = $ query, dialog

    setNode 'move',          '.move'
    setNode 'autohide',      '#autohide'
    setNode 'thread',        'select'
    setNode 'threadPar',     '#qr-thread-select'
    setNode 'close',         '.close'
    setNode 'form',          'form'
    setNode 'dumpButton',    '#dump-button'
    setNode 'urlButton',     '#url-button'
    setNode 'name',          '[data-name=name]'
    setNode 'email',         '[data-name=email]'
    setNode 'sub',           '[data-name=sub]'
    setNode 'com',           '[data-name=com]'
    setNode 'dumpList',      '#dump-list'
    setNode 'addPost',       '#add-post'
    setNode 'charCount',     '#char-count'
    setNode 'fileSubmit',    '#file-n-submit'
    setNode 'filename',      '#qr-filename'
    setNode 'fileContainer', '#qr-filename-container'
    setNode 'fileRM',        '#qr-filerm'
    setNode 'fileExtras',    '#qr-extras-container'
    setNode 'spoiler',       '#qr-file-spoiler'
    setNode 'spoilerPar',    '#qr-spoiler-label'
    setNode 'status',        '[type=submit]'
    setNode 'fileInput',     '[type=file]'

    rules = $('ul.rules').textContent.trim()

    match_min = rules.match(/.+smaller than (\d+)x(\d+).+/)
    match_max = rules.match(/.+greater than (\d+)x(\d+).+/)
    QR.min_width  = +match_min?[1] or 1
    QR.min_height = +match_min?[2] or 1
    QR.max_width  = +match_max?[1] or 10000
    QR.max_height = +match_max?[2] or 10000

    nodes.fileInput.max = $('input[name=MAX_FILE_SIZE]').value

    QR.max_size_video = 3145728
    QR.max_size_video_alt = 4194304
    QR.max_width_video = QR.max_height_video = 2048
    QR.max_duration_video = 120

    if Conf['Show New Thread Option in Threads']
      $.addClass QR.nodes.el, 'show-new-thread-option'

    if Conf['Show Name and Subject']
      $.addClass QR.nodes.name, 'force-show'
      $.addClass QR.nodes.sub, 'force-show'
      QR.nodes.email.placeholder = 'E-mail'

    QR.forcedAnon = !!$ 'form[name="post"] input[name="name"][type="hidden"]'
    if QR.forcedAnon
      $.addClass QR.nodes.el, 'forced-anon'

    QR.spoiler = !!$ '.postForm input[name=spoiler]'
    if QR.spoiler
      $.addClass QR.nodes.el, 'has-spoiler'
    else
      nodes.spoiler.parentElement.hidden = true

    if Conf['Dump List Before Comment']
      $.after nodes.name.parentElement, nodes.dumpList.parentElement
      nodes.addPost.tabIndex = 35

    if g.BOARD.ID is 'f' and g.VIEW isnt 'thread'
      nodes.flashTag = $.el 'select',
        name: 'filetag'

      $.extend nodes.flashTag, <%= html(
        '<option value="0">Hentai</option>' +
        '<option value="6">Porn</option>' +
        '<option value="1">Japanese</option>' +
        '<option value="2">Anime</option>' +
        '<option value="3">Game</option>' +
        '<option value="5">Loop</option>' +
        '<option value="4" selected>Other</option>'
      ) %>

      nodes.flashTag.dataset.default = '4'
      $.add nodes.form, nodes.flashTag

    QR.flagsInput()

    $.on nodes.filename.parentNode, 'click keydown', QR.openFileInput

    $.on nodes.autohide,   'change', QR.toggleHide
    $.on nodes.close,      'click',  QR.close
    $.on nodes.dumpButton, 'click',  -> nodes.el.classList.toggle 'dump'
    $.on nodes.urlButton,  'click',  QR.handleUrl
    $.on nodes.addPost,    'click',  -> new QR.post true
    $.on nodes.form,       'submit', QR.submit
    $.on nodes.filename,   'blur',   -> $.rmClass @, 'edit'
    $.on nodes.fileRM,     'click',  -> QR.selected.rmFile()
    $.on nodes.fileExtras, 'click',  (e) -> e.stopPropagation()
    $.on nodes.spoiler,    'change', -> QR.selected.nodes.spoiler.click()
    $.on nodes.fileInput,  'change', QR.handleFiles

    # mouseover descriptions
    items = ['spoilerPar', 'dumpButton', 'fileRM', 'urlButton']
    i = 0
    while name = items[i++]
      $.on nodes[name], 'mouseover', QR.mouseover

    # save selected post's data
    items = ['thread', 'name', 'email', 'sub', 'com', 'filename', 'flag']
    i = 0
    save = -> QR.selected.save @
    while name = items[i++]
      continue unless node = nodes[name]
      event = if node.nodeName is 'SELECT' then 'change' else 'input'
      $.on nodes[name], event, save
    $.on nodes['name'], 'blur', QR.tripcodeHider

    <% if (type === 'userscript') { %>
    if Conf['Remember QR Size']
      $.get 'QR Size', '', (item) ->
        nodes.com.style.cssText = item['QR Size']
      $.on nodes.com, 'mouseup', (e) ->
        return if e.button isnt 0
        $.set 'QR Size', @style.cssText
    <% } %>

    QR.generatePostableThreadsList()
    QR.persona.init()
    new QR.post true
    QR.status()
    QR.cooldown.init()
    QR.captcha.init()

    Rice.nodes dialog

    $.add d.body, dialog
    QR.captcha.setup()

    if Conf['Auto Hide QR']
      nodes.autohide.click()

    # Create a custom event when the QR dialog is first initialized.
    # Use it to extend the QR's functionalities, or for XTRM RICE.
    $.event 'QRDialogCreation', null, dialog

  tripcodeHider: ->
    check = /^.*##?.+/.test @value
    if check and !@.className.match "\\btripped\\b" then $.addClass @, 'tripped'
    else if !check and @.className.match "\\btripped\\b" then $.rmClass @, 'tripped'

  flags: ->
    select = $.el 'select',
      name:      'flag'
      className: 'flagSelector'

    fn = (val) ->
      $.add select, $.el 'option',
        value: val[0]
        textContent: val[1]

    fn flag for flag in [
      ['0',  'None']
      ['US', 'American']
      ['KP', 'Best Korean']
      ['BL', 'Black Nationalist']
      ['CM', 'Communist']
      ['CF', 'Confederate']
      ['RE', 'Conservative']
      ['EU', 'European']
      ['GY', 'Gay']
      ['PC', 'Hippie']
      ['IL', 'Israeli']
      ['DM', 'Liberal']
      ['RP', 'Libertarian']
      ['MF', 'Muslim']
      ['NZ', 'Nazi']
      ['OB', 'Obama']
      ['PR', 'Pirate']
      ['RB', 'Rebel']
      ['TP', 'Tea Partier']
      ['TX', 'Texan']
      ['TR', 'Tree Hugger']
      ['WP', 'White Supremacist']
    ]

    select

  flagsInput: ->
    {nodes} = QR
    return unless nodes
    if nodes.flag
      $.rm nodes.flag
      delete nodes.flag

#    # if false?
#    if g.BOARD.ID is 'pol'
#      flag = QR.flags()
#      flag.dataset.name    = 'flag'
#      flag.dataset.default = '0'
#      nodes.flag = flag
#      $.add nodes.form, flag

  submit: (e) ->
    e?.preventDefault()

    if QR.req
      QR.abort()
      return

    if QR.cooldown.seconds
      QR.cooldown.auto = !QR.cooldown.auto
      QR.status()
      return

    post = QR.posts[0]
    post.forceSave()
    if g.BOARD.ID is 'f' and g.VIEW isnt 'thread'
      filetag = QR.nodes.flashTag.value
    threadID = post.thread
    thread = g.BOARD.threads[threadID]

    # prevent errors
    if threadID is 'new'
      threadID = null
      if g.BOARD.ID is 'vg' and !post.sub
        err = 'New threads require a subject.'
      else unless post.file or textOnly = !!$ 'input[name=textonly]', $.id 'postForm'
        err = 'No file selected.'
    else if g.BOARD.threads[threadID].isClosed
      err = 'You can\'t reply to this thread anymore.'
    else unless post.com or post.file
      err = 'No file selected.'
    else if post.file and thread.fileLimit
      err = 'Max limit of image replies has been reached.'

    if QR.captcha.isEnabled and !err
      captcha = QR.captcha.getOne()
      err = 'No valid captcha.' unless captcha

    QR.cleanNotifications()
    if err
      # stop auto-posting
      QR.cooldown.auto = false
      QR.status()
      QR.error err
      return

    # Enable auto-posting if we have stuff to post, disable it otherwise.
    QR.cooldown.auto = QR.posts.length > 1
    if Conf['Auto Hide QR'] and !QR.cooldown.auto
      QR.hide()
    if !QR.cooldown.auto and $.x 'ancestor::div[@id="qr"]', d.activeElement
      # Unfocus the focused element if it is one within the QR and we're not auto-posting.
      d.activeElement.blur()

    post.lock()

    formData =
      resto:    threadID
      name:     post.name unless QR.forcedAnon
      email:    post.email
      sub:      post.sub unless QR.forcedAnon or threadID
      com:      post.com
      upfile:   post.file
      filetag:  filetag
      spoiler:  post.spoiler
      flag:     post.flag
      textonly: textOnly
      mode:     'regist'
      pwd:      QR.persona.pwd

    options =
      responseType: 'document'
      withCredentials: true
      onload: QR.response
      onerror: ->
        # Connection error, or www.4chan.org/banned
        delete QR.req
        post.unlock()
        QR.cooldown.auto = false
        QR.status()
        QR.error $.el 'span',
          <%= html(
            meta.name + ' encountered an error while posting. ' +
            '[<a href="//4chan.org/banned" target="_blank">Banned?</a>] ' +
            '[<a href="${g.FAQ}#what-does-4chan-x-encountered-an-error-while-posting-please-try-again-mean" target="_blank">More info</a>]'
          ) %>
    extra =
      form: $.formData formData
      upCallbacks:
        onload: ->
          # Upload done, waiting for server response.
          QR.req.isUploadFinished = true
          QR.req.uploadEndTime    = Date.now()
          QR.req.progress = '...'
          QR.status()
        onprogress: (e) ->
          # Uploading...
          QR.req.progress = "#{Math.round e.loaded / e.total * 100}%"
          QR.status()

    cb = (response) ->
      extra.form.append 'g-recaptcha-response', response if response?
      QR.req = $.ajax "https://sys.4chan.org/#{g.BOARD}/post", options, extra
      QR.req.progress = '...'

    if typeof captcha is 'function'
      # Wait for captcha to be verified before submitting post.
      QR.req =
        progress: '...'
        abort: -> cb = null
      captcha (response) ->
        if response
          cb? response
        else
          delete QR.req
          post.unlock()
          QR.cooldown.auto = !!QR.captcha.captchas.length
          QR.status()
    else
      cb captcha

    # Starting to upload might take some time.
    # Provide some feedback that we're starting to submit.
    QR.status()

  response: ->
    {req} = QR
    delete QR.req

    post = QR.posts[0]
    post.unlock()

    resDoc  = req.response
    if ban  = $ '.banType', resDoc # banned/warning
      board = $('.board', resDoc).innerHTML
      err   = $.el 'span',
        if ban.textContent.toLowerCase() is 'banned'
          <%= html('You are banned on &{$(".board", resDoc)}! ;_;<br>Click <a href="//www.4chan.org/banned" target="_blank">here</a> to see the reason.') %>
        else
          <%= html('You were issued a warning on &{$(".board", resDoc)} as &{$(".nameBlock", resDoc)}.<br>Reason: &{$(".reason", resDoc)}') %>
    else if err = resDoc.getElementById 'errmsg' # error!
      $('a', err)?.target = '_blank' # duplicate image link
    else if resDoc.title isnt 'Post successful!'
      err = 'Connection error with sys.4chan.org.'
    else if req.status isnt 200
      err = "Error #{req.statusText} (#{req.status})"

    if err
      if /captcha|verification/i.test(err.textContent) or err is 'Connection error with sys.4chan.org.'
        # Remove the obnoxious 4chan Pass ad.
        if /mistyped/i.test err.textContent
          err = 'You seem to have mistyped the CAPTCHA.'
        else if /expired/i.test err.textContent
          err = 'This CAPTCHA is no longer valid because it has expired.'
        # Enable auto-post if we have some cached captchas.
        QR.cooldown.auto = if QR.captcha.isEnabled
          !!QR.captcha.captchas.length
        else if err is 'Connection error with sys.4chan.org.'
          true
        else
          # Something must've gone terribly wrong if you get captcha errors without captchas.
          # Don't auto-post indefinitely in that case.
          false
        # Too many frequent mistyped captchas will auto-ban you!
        # On connection error, the post most likely didn't go through.
        QR.cooldown.addDelay post, 2
      else if err.textContent and (m = err.textContent.match /wait\s+(\d+)\s+second/i) and !/duplicate/i.test err.textContent
        QR.cooldown.auto = if QR.captcha.isEnabled
          !!QR.captcha.captchas.length
        else
          true
        QR.cooldown.addDelay post, +m[1]
        QR.captcha.setup (d.activeElement is QR.nodes.status)
      else # stop auto-posting
        QR.cooldown.auto = false
      QR.status()
      QR.error err
      return

    h1 = $ 'h1', resDoc
    QR.cleanNotifications()

    if Conf['Posting Success Notifications']
      QR.notifications.push new Notice 'success', h1.textContent, 5

    QR.persona.set post

    [_, threadID, postID] = h1.nextSibling.textContent.match /thread:(\d+),no:(\d+)/
    postID   = +postID
    threadID = +threadID or postID
    isReply  = threadID isnt postID

    QR.db.set
      boardID: g.BOARD.ID
      threadID: threadID
      postID: postID
      val: true

    ThreadUpdater.postID = postID

    # Post/upload confirmed as successful.
    $.event 'QRPostSuccessful', {
      boardID: g.BOARD.ID
      threadID
      postID
    }
    $.event 'QRPostSuccessful_', {boardID: g.BOARD.ID, threadID, postID}

    # Enable auto-posting if we have stuff left to post, disable it otherwise.
    postsCount = QR.posts.length - 1
    QR.cooldown.auto = postsCount and isReply
    if QR.cooldown.auto and QR.captcha.isEnabled and (captchasCount = QR.captcha.captchas.length) < 3 and captchasCount < postsCount
      notif = new Notification 'Quick reply warning',
        body: "You are running low on cached captchas. Cache count: #{captchasCount}."
        icon: Favicon.logo
      notif.onclick = ->
        QR.open()
        window.focus()
        QR.captcha.setup true
      notif.onshow = ->
        setTimeout ->
          notif.close()
        , 7 * $.SECOND

    unless Conf['Persistent QR'] or postsCount
      QR.close()
    else
      post.rm()
      QR.captcha.setup(d.activeElement is QR.nodes.status)

    QR.cooldown.add req.uploadEndTime, threadID, postID

    URL = if threadID is postID # new thread
      window.location.origin + Build.path g.BOARD.ID, threadID
    else if g.VIEW is 'index' and !QR.cooldown.auto and Conf['Open Post in New Tab'] # replying from the index
      window.location.origin + Build.path g.BOARD.ID, threadID, postID

    if URL
      if Conf['Open Post in New Tab'] or postsCount
        $.open URL
      else
        window.location = URL

    QR.status()

  abort: ->
    if QR.req and !QR.req.isUploadFinished
      QR.req.abort()
      delete QR.req
      QR.posts[0].unlock()
      QR.cooldown.auto = false
      QR.notifications.push new Notice 'info', 'QR upload aborted.', 5
    QR.status()

  mouseover: (e) ->
    mouseover = $.el 'div',
      id:        'mouseover'
      className: 'dialog'

    $.add Header.hover, mouseover

    mouseover.innerHTML = @nextElementSibling.innerHTML

    UI.hover
      root:         @
      el:           mouseover
      latestEvent:  e
      endEvents:    'mouseout'
      asapTest: ->  true
      offsetX: 15
      offsetY: -5

    return
