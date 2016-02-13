Index =
  showHiddenThreads: false
  init: ->
    return unless Conf['JSON Navigation'] and g.VIEW in ['index', 'thread'] and g.BOARD.ID isnt 'f'

    @board = "#{g.BOARD}"

    @button = $.el 'a',
      className: 'index-refresh-shortcut fa'
      title: 'Refresh Index'
      href: 'javascript:;'
      textContent: "\uf021"
    $.on @button, 'click', @update
    Header.addShortcut @button, 1

    @db = new DataBoard 'pinnedThreads'
    Thread.callbacks.push
      name: 'Thread Pinning'
      cb:   @threadNode

    CatalogThread.callbacks.push
      name: 'Catalog Features'
      cb:   @catalogNode

    modeEntry =
      el: $.el 'span', textContent: 'Index mode'
      subEntries: [
        { el: $.el 'label', innerHTML: '<input type=radio name="Index Mode" value="paged"> Paged' }
        { el: $.el 'label', innerHTML: '<input type=radio name="Index Mode" value="infinite"> Infinite scrolling' }
        { el: $.el 'label', innerHTML: '<input type=radio name="Index Mode" value="all pages"> All threads' }
      ]

    for label in modeEntry.subEntries
      input = label.el.firstChild
      input.checked = Conf['Index Mode'] is input.value
      $.on input, 'change', $.cb.value
      $.on input, 'change', @cb.mode

    sortEntry =
      el: $.el 'span', textContent: 'Sort by'

    threadNumEntry =
      el: $.el 'span', textContent: 'Threads per page'
      subEntries: [
        { el: $.el 'label', innerHTML: '<input type=number min=0 name="Threads per Page">', title: 'Use 0 for default value' }
      ]
    threadsNumInput = threadNumEntry.subEntries[0].el.firstChild
    threadsNumInput.value = Conf['Threads per Page']
    $.on threadsNumInput, 'change', $.cb.value
    $.on threadsNumInput, 'change', @cb.threadsNum

    targetEntry  = el: UI.checkbox 'Open threads in a new tab', 'Open threads in a new tab'
    repliesEntry = el: UI.checkbox 'Show Replies',              'Show replies'
    pinEntry     = el: UI.checkbox 'Pin Watched Threads',       'Pin watched threads'
    anchorEntry  = el: UI.checkbox 'Anchor Hidden Threads',     'Anchor hidden threads'
    refNavEntry  = el: UI.checkbox 'Refreshed Navigation',      'Refreshed navigation'

    targetEntry.el.title = 'Catalog-only setting.'
    pinEntry.el.title    = 'Move watched threads to the start of the index.'
    anchorEntry.el.title = 'Move hidden threads to the end of the index.'
    refNavEntry.el.title = 'Refresh index when navigating through pages.'

    for label in [targetEntry, repliesEntry, pinEntry, anchorEntry, refNavEntry]
      input = label.el.firstChild
      {name} = input
      input.checked = Conf[name]
      $.on input, 'change', $.cb.checked
      switch name
        when 'Open threads in a new tab'
          $.on input, 'change', @cb.target
        when 'Show Replies'
          $.on input, 'change', @cb.replies
        when 'Pin Watched Threads', 'Anchor Hidden Threads'
          $.on input, 'change', @cb.sort

    Header.menu.addEntry
      el: $.el 'span',
        textContent: 'Index Navigation'
      order: 98
      subEntries: [threadNumEntry, targetEntry, repliesEntry, pinEntry, anchorEntry, refNavEntry]

    $.addClass doc, 'index-loading'

    @root = $.el 'div', className: 'board'
    @pagelist = $.el 'div',
      className: 'pagelist'
      hidden: true,
    $.extend @pagelist, <%= importHTML('Features/Index-pagelist') %>

    @navLinks = $.el 'div',
      className: 'navLinks',  
    $.extend @navLinks, <%= importHTML('Features/Index-navlinks') %>

    @timeEl = $ 'time#index-last-refresh', @navLinks

    @searchInput = $ '#index-search', @navLinks

    @searchTest true

    @hideLabel   = $ '#hidden-label', @navLinks
    @selectMode  = $ '#index-mode',   @navLinks
    @selectSort  = $ '#index-sort',   @navLinks
    @selectSize  = $ '#index-size',   @navLinks

    $.on @searchInput, 'input', @onSearchInput
    $.on $('#index-search-clear', @navLinks), 'click', @clearSearch
    $.on $('#hidden-toggle a',    @navLinks), 'click', @cb.toggleHiddenThreads

    for select in [@selectMode, @selectSort, @selectSize]
      select.value = Conf[select.name]
      $.on select, 'change', $.cb.value

    $.on @selectMode, 'change', @cb.mode
    $.on @selectSort, 'change', @cb.sort
    $.on @selectSize, 'change', @cb.size

    Rice.nodes @navLinks

    @currentPage = @getCurrentPage()

    $.on d, 'scroll', @scroll
    $.on window, 'focus', @updateIfNeeded if Conf['Update Stale Index']
    $.on @pagelist, 'click', @cb.pageNav

    returnLink = $.el 'a',
      id: 'returnIcon'
      className: 'a-icon'
      href: '.././'

    @catalogLink = $.el 'a',
      id: 'catalogIcon'
      className: 'a-icon'
      href: "//boards.4chan.org/#{g.BOARD.ID}/"

    @catalogLink.dataset.indexMode = 'catalog'

    $.on returnLink, 'click', (e) ->
      if g.VIEW is 'index'
        Index.setIndexMode Conf['Previous Index Mode']
        e.preventDefault()
        return
      Navigate.navigate.call @, e

    $.on @catalogLink, 'click', Navigate.navigate

    Header.addShortcut @catalogLink, true
    Header.addShortcut returnLink,   true

    if g.VIEW is 'index'
      @update()
      @cb.toggleCatalogMode()

    $.asap (-> $('.board', doc) or d.readyState isnt 'loading'), ->
      $.rm navLink for navLink in $$ '.navLinks'
      $.id('search-box')?.parentNode.remove()
      $.after $.x('child::form/preceding-sibling::hr[1]'), Index.navLinks

      return if g.VIEW isnt 'index' or Index.root.parentElement

      board = $ '.board'
      $.replace board, Index.root
      $.event 'PostsInserted'
      # Hacks:
      # - When removing an element from the document during page load,
      #   its ancestors will still be correctly created inside of it.
      # - Creating loadable elements inside of an origin-less document
      #   will not download them.
      # - Combine the two and you get a download canceller!
      #   Does not work on Firefox unfortunately. bugzil.la/939713
      d.implementation.createDocument(null, null, null).appendChild board

    $.asap (-> $('.pagelist', doc) or d.readyState isnt 'loading'), ->
      if pagelist = $('.pagelist')
        $.replace pagelist, Index.pagelist
      else
        $.after $.id('delform'), Index.pagelist
      $.rmClass doc, 'index-loading'

  scroll: ->
    return if Index.req or Conf['Index Mode'] isnt 'infinite' or (window.scrollY <= doc.scrollHeight - (300 + window.innerHeight)) or g.VIEW is 'thread'
    Index.currentPage = Index.getCurrentPage() + 1 # Avoid having to pushState to keep track of the current page
    return Index.endNotice() if Index.currentPage >= Index.pagesNum
    Index.buildIndex true

  endNotice: do ->
    notify = false
    reset = -> notify = false
    return ->
      return if notify
      notify = true
      new Notice 'info', "Last page reached.", 2
      setTimeout reset, 3 * $.SECOND

  menu:
    init: ->
      return if g.VIEW isnt 'index' or !Conf['Menu'] or g.BOARD.ID is 'f'

      Menu.menu.addEntry
        el: $.el 'a', href: 'javascript:;'
        order: 19
        open: ({thread}) ->
          return false if Conf['Index Mode'] isnt 'catalog'
          @el.textContent = if thread.isPinned
            'Unpin thread'
          else
            'Pin thread'
          $.off @el, 'click', @cb if @cb
          @cb = ->
            $.event 'CloseMenu'
            Index.togglePin thread
          $.on @el, 'click', @cb

  threadNode: ->
    return if g.VIEW isnt 'index'
    return unless Index.db.get {boardID: @board.ID, threadID: @ID}
    @pin()

  catalogNode: ->
    $.on @nodes.thumb, 'click', Index.onClick
    return if Conf['Image Hover in Catalog']
    $.on @nodes.thumb, 'mouseover', Index.onOver

  onClick: (e) ->
    return if e.button isnt 0
    thread = g.threads[@parentNode.dataset.fullID]
    if e.shiftKey
      PostHiding.toggle thread.OP
    else if e.altKey
      Index.togglePin thread
    else
      return Navigate.navigate.call @, e
    e.preventDefault()

  onOver: (e) ->
    # 4chan's less than stellar CSS forces us to include a .post and .postInfo
    # in order to have proper styling for the .nameBlock's content.
    {nodes} = g.threads[@parentNode.dataset.fullID].OP
    el = $.el 'div',
      innerHTML: '<div class=post><div class=postInfo></div></div>'
      className: 'thread-info dialog'
      hidden: true
    $.add el.firstElementChild.firstElementChild, [
      $('.nameBlock', nodes.info).cloneNode true
      $.tn ' '
      nodes.date.cloneNode true
    ]
    $.add Header.hover, el
    UI.hover
      root: @
      el: el
      latestEvent: e
      endEvents: 'mouseout'
      asapTest: -> true
      offsetX: 15
      offsetY: -20
    setTimeout (-> el.hidden = false if el.parentNode), .25 * $.SECOND

  togglePin: (thread) ->
    data =
      boardID:  thread.board.ID
      threadID: thread.ID
    if thread.isPinned
      thread.unpin()
      Index.db.delete data
    else
      thread.pin()
      data.val = true
      Index.db.set data
    Index.sort()
    Index.buildIndex()

  setIndexMode: (mode) ->
    Index.selectMode.value = mode
    $.event 'change', null, Index.selectMode

  cycleSortType: ->
    types = (option for option in Index.selectSort.options when not option.disabled)
    for type, i in types
      break if type.selected
    types[(i + 1) % types.length].selected = true
    $.event 'change', null, Index.selectSort

  catalogSwitch: ->
    $.get 'JSON Navigation', true, (items) ->
      return if !items['JSON Navigation']
      $.set 'Index Mode', 'catalog'
      {hash} = window.location
      window.location = './' + hash

  searchTest: (init) ->
    return false unless hash = window.location.hash
    return false unless match = hash.match /s=([\w\s\n]+)/
    @searchInput.value = match[1]
    if init
      $.on d, '4chanXInitFinished', Index.onSearchInput
    else
      Index.onSearchInput()
    return true

  setupNavLinks: ->
    for el in $$ '.navLinks.desktop > a'
      if /\/catalog$/.test el.pathname
        el.href = '.././'
      $.on el, 'click', ->
        switch @textContent
          when 'Return'
            $.set 'Index Mode', Conf['Previous Index Mode']
          when 'Catalog'
            $.set 'Index Mode', 'catalog'
    return

  cb:
    toggleCatalogMode: ->
      if Conf['Index Mode'] is 'catalog'
        $.addClass doc, 'catalog-mode'
      else
        $.rmClass doc, 'catalog-mode'
      Index.cb.size()

    toggleHiddenThreads: ->
      $('#hidden-toggle a', Index.navLinks).textContent = if Index.showHiddenThreads = !Index.showHiddenThreads
        'Hide'
      else
        'Show'
      Index.sort()
      if Conf['Index Mode'] is 'paged' and Index.getCurrentPage() > 1
        Index.pageNav 1
      else
        Index.buildIndex()

    mode: (e) ->
      Index.cb.toggleCatalogMode()
      Index.togglePagelist()
      Index.buildIndex() if e
      mode = Conf['Index Mode']
      if mode not in ['catalog', Conf['Previous Index Mode']]
        Conf['Previous Index Mode'] = mode
        $.set 'Previous Index Mode', mode

    sort: (e) ->
      Index.sort()
      Index.buildIndex() if e

    size: (e) ->
      if Conf['Index Mode'] isnt 'catalog'
        $.rmClass  Index.root,  'catalog-small'
        $.rmClass  Index.root,  'catalog-large'
      else if Conf['Index Size'] is 'small'
        $.addClass Index.root,  'catalog-small'
        $.rmClass  Index.root,  'catalog-large'
      else
        $.addClass Index.root,  'catalog-large'
        $.rmClass  Index.root,  'catalog-small'
      Index.buildIndex() if e

    threadsNum: ->
      return unless Conf['Index Mode'] is 'paged'
      Index.buildIndex()

    target: ->
      g.BOARD.threads.forEach (thread) ->
        return if !thread.catalogView
        {thumb} = thread.catalogView.nodes
        if Conf['Open threads in a new tab']
          thumb.target = '_blank'
        else
          thumb.removeAttribute 'target'

    replies: ->
      Index.buildThreads()
      Index.sort()
      Index.buildIndex()

    pageNav: (e) ->
      return if e.shiftKey or e.altKey or e.ctrlKey or e.metaKey or e.button isnt 0
      switch e.target.nodeName
        when 'BUTTON'
          e.target.blur()
          a = e.target.parentNode
        when 'A'
          a = e.target
        else
          return
      e.preventDefault()
      return if Index.cb.indexNav a, true
      Index.userPageNav +a.pathname.split('/')[2] or 1

    headerNav: (e) ->
      a = e.target
      return if e.button isnt 0 or a.nodeName isnt 'A' or a.hostname isnt 'boards.4chan.org'
      # Save settings
      onSameIndex = g.VIEW is 'index' and a.pathname.split('/')[1] is g.BOARD.ID
      needChange = Index.cb.indexNav a, onSameIndex
      # Do nav if this isn't a simple click, or different board.
      return if e.shiftKey or e.altKey or e.ctrlKey or e.metaKey or !onSameIndex or g.BOARD.ID is 'f'
      e.preventDefault()
      Index.update() unless needChange

    indexNav: (a, onSameIndex) ->
      {indexMode, indexSort} = a.dataset
      if indexMode and Conf['Index Mode'] isnt indexMode
        $.set 'Index Mode', indexMode
        Conf['Index Mode'] = indexMode
        if onSameIndex
          Index.selectMode.value = indexMode
          Index.cb.mode()
          needChange = true
      if indexSort and Conf['Index Sort'] isnt indexSort
        $.set 'Index Sort', indexSort
        Conf['Index Sort'] = indexSort
        if onSameIndex
          Index.selectSort.value = indexSort
          Index.cb.sort()
          needChange = true
      if needChange
        Index.buildIndex()
        Index.scrollToIndex()
      needChange

  scrollToIndex: ->
    Header.scrollToIfNeeded Index.navLinks

  getCurrentPage: ->
    if Conf['Index Mode'] in ['all pages', 'catalog']
      return 1
    if Conf['Index Mode'] is 'infinite' and Index.currentPage
      return Index.currentPage
    +window.location.pathname.split('/')[2] or 1

  userPageNav: (pageNum) ->
    Navigate.pushState if pageNum is 1 then './' else pageNum
    if Conf['Refreshed Navigation'] and Conf['Index Mode'] isnt 'all pages'
      Index.update pageNum
    else
      Index.pageNav pageNum

  pageNav: (pageNum) ->
    return if Index.currentPage is pageNum and not Index.root.parentElement
    Navigate.pushState if pageNum is 1 then './' else pageNum
    Index.pageLoad pageNum

  pageLoad: (pageNum) ->
    Index.currentPage = pageNum
    return if Conf['Index Mode'] is 'all pages'
    Index.buildIndex()
    Index.scrollToIndex()

  getThreadsNumPerPage: ->
    if Conf['Threads per Page'] > 0
      +Conf['Threads per Page']
    else
      Index.threadsNumPerPage

  getPagesNum: ->
    Math.ceil Index.sortedThreads.length / Index.getThreadsNumPerPage()

  getMaxPageNum: ->
    min = 1
    max = +Index.getPagesNum()
    if min < max then max else
      min
  togglePagelist: ->
    Index.pagelist.hidden = Conf['Index Mode'] isnt 'paged'

  buildPagelist: ->
    pagesRoot = $ '.pages', Index.pagelist
    maxPageNum = Index.getMaxPageNum()
    if pagesRoot.childElementCount isnt maxPageNum
      nodes = []
      for i in [1..maxPageNum] by 1
        a = $.el 'a',
          textContent: i
          href: if i is 1 then './' else i
        nodes.push $.tn('['), a, $.tn '] '
      $.rmAll pagesRoot
      $.add pagesRoot, nodes
    Index.togglePagelist()

  setPage: (pageNum = Index.getCurrentPage()) ->
    Index.currentPage = pageNum
    maxPageNum = Index.getMaxPageNum()
    pagesRoot  = $ '.pages', Index.pagelist

    # Previous/Next buttons
    prev = pagesRoot.previousElementSibling.firstElementChild
    href = Math.max pageNum - 1, 1
    prev.href = if href is 1 then './' else href
    prev.firstChild.disabled = href is pageNum

    next = pagesRoot.nextElementSibling.firstElementChild
    href = Math.min pageNum + 1, maxPageNum
    next.href = if href is 1 then './' else href
    next.firstChild.disabled = href is pageNum

    # <strong> current page
    if strong = $ 'strong', pagesRoot
      return if +strong.textContent is pageNum
      $.replace strong, strong.firstChild
    else
      strong = $.el 'strong'

    # If coming in from a Navigate.navigate, this could break.
    return unless a = pagesRoot.children[pageNum - 1]

    $.before a, strong
    $.add strong, a

  updateHideLabel: ->
    hiddenCount = 0
    for threadID in g.BOARD.threads.keys
      thread = g.BOARD.threads[threadID]
      hiddenCount++ if thread.isHidden and threadID in Index.liveThreadData.keys
    unless hiddenCount
      Index.hideLabel.hidden = true
      Index.cb.toggleHiddenThreads() if Index.showHiddenThreads
      return
    Index.hideLabel.hidden = false
    $('#hidden-count', Index.hideLabel).textContent = if hiddenCount is 1
      '1 hidden thread'
    else
      "#{hiddenCount} hidden threads"

  updateIfNeeded: ->
    {timeEl} = Index
    needed =
      # we're on the index,
      g.VIEW is 'index' and
      # not currently refreshing
      !Index.req and
      timeEl.dataset.utc and
      # more than 10 minutes have elapsed since the last refresh.
      timeEl.dataset.utc < Date.now() - (10 * $.MINUTE)
    Index.update() if needed

  update: (pageNum) ->
    return unless navigator.onLine
    if g.VIEW is 'thread'
      ThreadUpdater.update() if Conf['Thread Updater']
      return
    unless d.readyState is 'loading' or Index.root.parentElement
      $.replace $('.board'), Index.root
    Index.currentPage = 1
    Index.req?.abort()
    Index.notice?.close()

    {sortedThreads} = Index
    if sortedThreads
      board = sortedThreads[0].board.ID

    # This notice only displays if Index Refresh is taking too long
    now = Date.now()
    $.ready ->
      Index.nTimeout = setTimeout (->
        if Index.req and !Index.notice
          Index.notice = new Notice 'info', 'Refreshing index...', 2
      ), 3 * $.SECOND - (Date.now() - now)

    pageNum = '' if typeof pageNum isnt 'number' # event
    onload = (e) -> Index.load e, pageNum
    Index.req = $.ajax "//a.4cdn.org/#{g.BOARD.ID}/catalog.json",
      onabort:   onload
      onloadend: onload
      onerror:   onload
    ,
      whenModified: board is g.BOARD.ID
    $.addClass Index.button, 'fa-spin'

  load: (e, pageNum) ->
    $.rmClass Index.button, 'fa-spin'
    {req, notice, nTimeout} = Index
    clearTimeout nTimeout if nTimeout
    delete Index.nTimeout
    delete Index.req
    delete Index.notice

    if e.type is 'abort'
      req.onloadend = null
      notice.close()
      return

    if req.status not in [200, 304]
      err = "Index refresh failed. Error #{req.statusText} (#{req.status})"
      if notice
        notice.setType 'warning'
        notice.el.lastElementChild.textContent = err
        setTimeout notice.close, $.SECOND
      else
        new Notice 'warning', err, 1
      return

    Navigate.title()

    try
      pageNum or= 1
      if req.status is 200
        Index.parse req.response, pageNum
      else if req.status is 304
        if Index.currentPage is pageNum
          Index.buildIndex()
        else
          Index.pageNav pageNum
    catch err
      c.error "Index failure: #{err.message}", err.stack
      # network error or non-JSON content for example.
      if notice
        notice.setType 'error'
        notice.el.lastElementChild.textContent = 'Index refresh failed.'
        setTimeout notice.close, $.SECOND
      else
        new Notice 'error', 'Index refresh failed.', 1
      return

    {timeEl} = Index
    timeEl.dataset.utc = Date.parse req.getResponseHeader 'Last-Modified'
    RelativeDates.update timeEl
    Index.scrollToIndex()

  parse: (pages, pageNum) ->
    $.cleanCache (url) -> /^\/\/a\.4cdn\.org\//.test url
    Index.parseThreadList pages
    Index.buildThreads()
    Index.sort()
    if pageNum? and Index.currentPage isnt pageNum
      Index.pageNav pageNum
      return
    Index.buildIndex()

  parseThreadList: (pages) ->
    Index.threadsNumPerPage = pages[0].threads.length

    live = new SimpleDict()
    i    = 0
    while page = pages[i++]
      j = 0
      {threads} = page
      while thread = threads[j++]
        live.push thread.no, thread

    Index.liveThreadData = live

    g.BOARD.threads.forEach (thread) ->
      thread.collect() unless thread.ID in Index.liveThreadData.keys

  buildThreads: ->
    threads = []
    posts   = []
    errors  = null

    Index.liveThreadData.forEach (threadData) ->
      threadRoot = Build.thread g.BOARD, threadData
      if thread = g.BOARD.threads[threadData.no]
        thread.setPage i // Index.threadsNumPerPage + 1
        thread.setCount 'post', threadData.replies + 1,                threadData.bumplimit
        thread.setCount 'file', threadData.images  + !!threadData.ext, threadData.imagelimit
        thread.setStatus 'Sticky', !!threadData.sticky
        thread.setStatus 'Closed', !!threadData.closed
      else
        thread = new Thread threadData.no, g.BOARD
        threads.push thread

      # XXX some issue with Chrome 48's garbage collection being too aggressive?
      thread.threadRoot = threadRoot 

      return if thread.ID of thread.posts

      try
        posts.push new Post $('.opContainer', threadRoot), thread, g.BOARD

      catch err
        # Skip posts that we failed to parse.
        errors = [] unless errors
        errors.push
          message: "Parsing of Thread No.#{thread} failed. Thread will be skipped."
          error: err

    Main.handleErrors  errors if errors
    Thread.callbacks.execute threads
    Post.callbacks.execute   posts
    Index.updateHideLabel()

    $.event 'IndexRefresh'

  buildReplies: (thread) ->
    return unless Conf['Show Replies']
    posts = []
    return unless lastReplies = Index.liveThreadData[thread.ID].last_replies
    nodes = []
        
    for data in lastReplies
      if post = thread.posts[data.no]
        nodes.push post.nodes.root
        continue
      nodes.push node = Build.postFromObject data, thread.board.ID
      try
        posts.push new Post node, thread, thread.board
      catch err
        # Skip posts that we failed to parse.
        errors = [] unless errors
        errors.push
          message: "Parsing of Post No.#{data.no} failed. Post will be skipped."
          error: err
    
    $.add thread.OP.nodes.root.parentElement, nodes

    Main.handleErrors errors if errors
    Post.callbacks.execute posts

  buildCatalogViews: ->
    catalogThreads = []
    nodes = []
    i = 0
    size = if Conf['Index Size'] is 'small' then 150 else 250
    while thread = Index.sortedThreads[i++]
      if !thread.catalogView
        catalogThreads.push new CatalogThread Build.catalogThread(thread), thread
      {root} = thread.catalogView.nodes
      Index.sizeSingleCatalogNode root, size
      nodes.push root
    CatalogThread.callbacks.execute catalogThreads
    return nodes

  sizeSingleCatalogNode: (node, size) ->
    thumb = node.firstElementChild.firstElementChild
    {width, height} = thumb.dataset
    return unless width
    ratio = size / Math.max width, height
    thumb.style.width  = width  * ratio + 'px'
    thumb.style.height = height * ratio + 'px'

  sort: ->
    sortedThreads   = []
    sortedThreadIDs = []

    liveData = []
    Index.liveThreadData.forEach (data) -> liveData.push data

    {
      'bump': ->
        sortedThreadIDs = Index.liveThreadData.keys
      'lastreply': ->
        liveData.sort (a, b) ->
          [..., a] = a.last_replies if 'last_replies' of a
          [..., b] = b.last_replies if 'last_replies' of b
          b.no - a.no
        i = 0
        while data = liveData[i++]
          sortedThreadIDs.push data.no
        return
      'birth': ->
        sortedThreadIDs = [Index.liveThreadData.keys...].sort (a, b) -> b - a
      'replycount': ->
        liveData.sort (a, b) -> b.replies - a.replies
        i = 0
        while data = liveData[i++]
          sortedThreadIDs.push data.no
        return
      'filecount': ->
        liveData = []
        Index.liveThreadData.forEach (data) -> liveData.push data
        liveData.sort (a, b) -> b.images - a.images
        i = 0
        while data = liveData[i++]
          sortedThreadIDs.push data.no
        return
    }[Conf['Index Sort']]()

    i = 0
    while threadID = sortedThreadIDs[i++]
      sortedThreads.push g.BOARD.threads[threadID]

    Index.sortedThreads = []
    i = 0
    while thread = sortedThreads[i++]
      Index.sortedThreads.push thread if thread.isHidden is Index.showHiddenThreads

    if Index.isSearching
      Index.sortedThreads = Index.querySearch(Index.searchInput.value) or Index.sortedThreads
    # Sticky threads
    Index.sortOnTop (thread) -> thread.isSticky
    # Highlighted threads
    Index.sortOnTop (thread) -> thread.isOnTop or Conf['Pin Watched Threads'] and ThreadWatcher.isWatched thread
    # Non-hidden threads
    Index.sortOnTop((thread) -> !thread.isHidden) if Conf['Anchor Hidden Threads']

  sortOnTop: (match) ->
    offset = 0
    topThreads    = []
    bottomThreads = []
    for thread, i in Index.sortedThreads
      (if match thread then topThreads else bottomThreads).push thread
    Index.sortedThreads = topThreads.concat bottomThreads

  buildIndex: (infinite) ->
    {sortedThreads} = Index
    nodes = []
    switch Conf['Index Mode']
      when 'paged', 'infinite'
        pageNum = Index.getCurrentPage()
        threadsPerPage = Index.getThreadsNumPerPage()

        i       = threadsPerPage * (pageNum - 1)
        max     = i + threadsPerPage
        nodes = Index.processThreads sortedThreads, i, max

        Index.buildPagelist()
        Index.setPage pageNum

      when 'catalog'
        nodes = Index.buildCatalogViews()

      else
        nodes = Index.processThreads sortedThreads, 0, sortedThreads.length

    $.rmAll Index.root unless infinite
    $.add Index.root, nodes

  processThreads: (threads, i, max) ->
    nodes = []
    while i < max and thread = threads[i++]
      nodes.push thread.OP.nodes.root.parentNode, $.el 'hr'
      Index.buildReplies thread
    nodes

  isSearching: false

  clearSearch: ->
    Index.searchInput.value = null
    Index.onSearchInput()
    Index.searchInput.focus()

  onSearchInput: ->
    if Index.isSearching = !!Index.searchInput.value.trim()
      unless Index.searchInput.dataset.searching
        Index.searchInput.dataset.searching = 1
        Index.pageBeforeSearch = Index.getCurrentPage()
        Index.setPage pageNum = 1
      else
        unless Conf['Index Mode'] is 'infinite'
          pageNum = Index.getCurrentPage()

    else
      return unless Index.searchInput.dataset.searching
      pageNum = Index.pageBeforeSearch
      delete Index.pageBeforeSearch
      <% if (type === 'userscript') { %>
      # XXX https://github.com/greasemonkey/greasemonkey/issues/1571
      Index.searchInput.removeAttribute 'data-searching'
      <% } else { %>
      delete Index.searchInput.dataset.searching
      <% } %>
    Index.sort()
    if Conf['Index Mode'] in ['paged', 'infinite'] and Index.currentPage not in [pageNum, Index.getMaxPageNum()]
      # Go to the last available page if we were past the limit.
      Index.pageNav pageNum
    else
      Index.buildIndex()
      Index.setPage()

  querySearch: (query) ->
    return unless keywords = query.toLowerCase().match /\S+/g
    Index.search keywords

  search: (keywords) ->
    filtered = []
    i = 0
    {sortedThreads} = Index
    while thread = sortedThreads[i++]
      filtered.push thread if Index.searchMatch thread, keywords
    Index.sortedThreads = filtered

  searchMatch: (thread, keywords) ->
    {info, file} = thread.OP
    text = []
    for key in ['comment', 'subject', 'name', 'tripcode', 'email']
      text.push info[key] if key of info
    text.push file.name if file
    text = text.join(' ').toLowerCase()
    for keyword in keywords
      return false if -1 is text.indexOf keyword
    return true
