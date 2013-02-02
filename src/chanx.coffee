Markdown =
  format: (text) ->
    tag_patterns =
      bi:   /(\*\*\*|___)(?=\S)([^\r\n]*?\S)\1/g
      b:    /(\*\*|__)(?=\S)([^\r\n]*?\S)\1/g
      i:    /(\*|_)(?=\S)([^\r\n]*?\S)\1/g
      code: /(`)(?=\S)([^\r\n]*?\S)\1/g
      ds:   /(\|\||__)(?=\S)([^\r\n]*?\S)\1/g

    for tag, pattern of tag_patterns
      text =
        if text
          text.replace pattern, Markdown.unicode_convert
        else
          '\u0020'
    text

  unicode_convert: (str, tag, inner) ->
    fmt =
      switch tag
        when '_', '*'
          'i'
        when '__', '**'
          'b'
        when '___', '***'
          'bi'
        when '||'
          'ds'
        when '`', '```'
          'code'

    #Unicode codepoints for the characters '0', 'A', and 'a'
    #http://en.wikipedia.org/wiki/Mathematical_Alphanumeric_Symbols
    codepoints =
      b:    [ 0x1D7CE, 0x1D400, 0x1D41A ] # MATHEMATICAL BOLD
      i:    [ 0x1D7F6, 0x1D434, 0x1D44E ] # MATHEMATICAL ITALIC
      bi:   [ 0x1D7CE, 0x1D468, 0x1D482 ] # MATHEMATICAL BOLD ITALIC
      code: [ 0x1D7F6, 0x1D670, 0x1D68A ] # MATHEMATICAL MONOSPACE
      ds:   [ 0x1D7D8, 0x1D538, 0x1D552 ] # I FUCKING LOVE CAPS LOCK

    charcodes = (inner.charCodeAt i for c, i in inner)

    codes = for charcode in charcodes
      if charcode >= 48 and charcode <= 57
        charcode - 48 + codepoints[fmt][0]
      else if charcode >= 65 and charcode <= 90
        charcode - 65 + codepoints[fmt][1]
      else if charcode >= 97 and charcode <= 122
        if charcode is 104 and tag is 'i'
          # http://blogs.msdn.com/b/michkap/archive/2006/04/21/580328.aspx
          # Mathematical small h -> planck constant
          0x210E
        else
          charcode - 97 + codepoints[fmt][2]
      else
        charcode

    unicode_text = codes.map(Markdown.ucs2_encode).join ''
    unicode_text = unicode_text.replace(/\x20/g, '\xA0')  if tag is 'code'
    unicode_text

  ucs2_encode: (value) ->
    # Translates Unicode codepoint integers directly into text. Javascript does this in an ugly fashion by default.
    ###
    From Punycode.js: https://github.com/bestiejs/punycode.js

    Copyright Mathias Bynens <http://mathiasbynens.be/>

    Permission is hereby granted, free of charge, to any person obtaining
    a copy of this software and associated documentation files (the
    "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish,
    distribute, sublicense, and/or sell copies of the Software, and to
    permit persons to whom the Software is furnished to do so, subject to
    the following conditions:

    The above copyright notice and this permission notice shall be
    included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
    EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF`
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
    NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
    LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
    OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
    WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    ###

    output = ''
    if value > 0xFFFF
      value  -= 0x10000
      output += String.fromCharCode value >>> 10 & 0x3FF | 0xD800
      value  =  0xDC00 | value & 0x3FF
    output += String.fromCharCode value

Filter =
  filters: {}
  init: ->
    for key of Config.filter
      @filters[key] = []
      for filter in Conf[key].split '\n'
        continue if filter[0] is '#'

        unless regexp = filter.match /\/(.+)\/(\w*)/
          continue

        # Don't mix up filter flags with the regular expression.
        filter = filter.replace regexp[0], ''

        # Do not add this filter to the list if it's not a global one
        # and it's not specifically applicable to the current board.
        # Defaults to global.
        boards = filter.match(/boards:([^;]+)/)?[1].toLowerCase() or 'global'
        unless boards is 'global' or boards.split(',').contains(g.BOARD)
          continue

        if key is 'md5'
          # MD5 filter will use strings instead of regular expressions.
          regexp = regexp[1]
        else
          try
            # Please, don't write silly regular expressions.
            regexp = RegExp regexp[1], regexp[2]
          catch err
            # I warned you, bro.
            alert err.message
            continue

        # Filter OPs along with their threads, replies only, or both.
        # Defaults to replies only.
        op = filter.match(/[^t]op:(yes|no|only)/)?[1] or 'no'

        # Overrule the `Show Stubs` setting.
        # Defaults to stub showing.
        stub = switch filter.match(/stub:(yes|no)/)?[1]
          when 'yes'
            true
          when 'no'
            false
          else
            Conf['Show Stubs']

        # Highlight the post, or hide it.
        # If not specified, the highlight class will be filter_highlight.
        # Defaults to post hiding.
        if hl = /highlight/.test filter
          hl  = filter.match(/highlight:(\w+)/)?[1] or 'filter_highlight'
          # Put highlighted OP's thread on top of the board page or not.
          # Defaults to on top.
          top = filter.match(/top:(yes|no)/)?[1] or 'yes'
          top = top is 'yes' # Turn it into a boolean

        @filters[key].push @createFilter regexp, op, stub, hl, top

      # Only execute filter types that contain valid filters.
      unless @filters[key].length
        delete @filters[key]

    if Object.keys(@filters).length
      Main.callbacks.push @node

  createFilter: (regexp, op, stub, hl, top) ->
    test =
      if typeof regexp is 'string'
        # MD5 checking
        (value) -> regexp is value
      else
        (value) -> regexp.test value
    settings =
      hide:  !hl
      stub:  stub
      class: hl
      top:   top
    (value, isOP) ->
      if isOP and op is 'no' or !isOP and op is 'only'
        return false
      unless test value
        return false
      settings

  node: (post) ->
    return if post.isInlined
    isOP = post.ID is post.threadID
    {root} = post
    for key of Filter.filters
      value = Filter[key] post
      if value is false
        # Continue if there's nothing to filter (no tripcode for example).
        continue
      for filter in Filter.filters[key]
        unless result = filter value, isOP
          continue

        # Hide
        if result.hide
          if isOP
            unless g.REPLY
              ThreadHiding.hide root.parentNode, result.stub
            else
              continue
          else
            ReplyHiding.hide post.root, result.stub
          return

        # Highlight
        $.addClass root, result.class

  name: (post) ->
    $('.name', post.el).textContent
  uniqueid: (post) ->
    if uid = $ '.posteruid', post.el
      return uid.textContent[5...-1]
    false
  tripcode: (post) ->
    if trip = $ '.postertrip', post.el
      return trip.textContent
    false
  mod: (post) ->
    if mod = $ '.capcode', post.el
      return mod.textContent
    false
  email: (post) ->
    if mail = $ '.useremail', post.el
      # remove 'mailto:'
      # decode %20 into space for example
      return decodeURIComponent mail.href[7..]
    false
  subject: (post) ->
    if (subject = $ '.postInfo .subject', post.el).textContent.length isnt 0
      return subject.textContent
    false
  comment: (post) ->
    text = []
    nodes = d.evaluate './/br|.//text()', post.blockquote, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null
    for i in [0...nodes.snapshotLength]
      text.push if data = nodes.snapshotItem(i).data then data else '\n'
    if (content = text.join '').length isnt 0
      return content
    false
  country: (post) ->
    if flag = $ '.countryFlag', post.el
      return flag.title
    false
  filename: (post) ->
    {fileInfo} = post
    if fileInfo
      if file = $ '.fileText > span', fileInfo
        return file.title
      else
        return fileInfo.firstElementChild.dataset.filename
    false
  dimensions: (post) ->
    {fileInfo} = post
    if fileInfo and match = fileInfo.textContent.match /\d+x\d+/
      return match[0]
    false
  filesize: (post) ->
    {img} = post
    if img
      return img.alt.replace 'Spoiler Image, ', ''
    false
  md5: (post) ->
    {img} = post
    if img
      return img.dataset.md5
    false

  menuInit: ->
    div = $.el 'div',
      textContent: 'Filter'

    entry =
      el: div
      open: -> true
      children: []

    for type in [
      ['Name',             'name']
      ['Unique ID',        'uniqueid']
      ['Tripcode',         'tripcode']
      ['Admin/Mod',        'mod']
      ['E-mail',           'email']
      ['Subject',          'subject']
      ['Comment',          'comment']
      ['Country',          'country']
      ['Filename',         'filename']
      ['Image dimensions', 'dimensions']
      ['Filesize',         'filesize']
      ['Image MD5',        'md5']
    ]
      # Add a sub entry for each filter type.
      entry.children.push(@createSubEntry(type[0], type[1]));

    Menu.addEntry entry

  createSubEntry: (text, type) ->
    el = $.el 'a',
      href: 'javascript:;'
      textContent: text
    # Define the onclick var outside of open's scope to $.off it properly.
    onclick = null

    open = (post) ->
      value = Filter[type] post
      return false if value is false
      $.off el, 'click', onclick
      onclick = ->
        # Convert value -> regexp, unless type is md5
        re = if type is 'md5' then value else value.replace ///
          /
          | \\
          | \^
          | \$
          | \n
          | \.
          | \(
          | \)
          | \{
          | \}
          | \[
          | \]
          | \?
          | \*
          | \+
          | \|
          ///g, (c) ->
            if c is '\n'
              '\\n'
            else if c is '\\'
              '\\\\'
            else
              "\\#{c}"

        re =
          if type is 'md5'
            "/#{value}/"
          else
            "/^#{re}$/"
        if /\bop\b/.test post.class
          re += ';op:yes'

        # Add a new line before the regexp unless the text is empty.
        save = if save = $.get type, '' then "#{save}\n#{re}" else re
        $.set type, save

        # Open the options and display & focus the relevant filter textarea.
        Options.dialog()
        select = $ 'select[name=filter]', $.id 'options'
        select.value = type
        $.event select, new Event 'change'
        $.id('filter_tab').checked = true
        ta = select.nextElementSibling
        tl = ta.textLength
        ta.setSelectionRange tl, tl
        ta.focus()
      $.on el, 'click', onclick
      true

    return el: el, open: open

StrikethroughQuotes =
  init: ->
    Main.callbacks.push @node

  node: (post) ->
    return if post.isInlined
    for quote in post.quotes
      continue unless quote.hash and (el = $.id quote.hash[1..]) and quote.hostname is 'boards.4chan.org' and !/catalog$/.test(quote.pathname) and el.hidden
      $.addClass quote, 'filtered'
      if Conf['Recursive Filtering'] and post.ID isnt post.threadID
        show_stub = !!$.x 'preceding-sibling::div[contains(@class,"stub")]', el
        ReplyHiding.hide post.root, show_stub
    return

ExpandComment =
  init: ->
    for a in $$ '.abbr'
      $.on a.firstElementChild, 'click', ExpandComment.expand
    return

  expand: (e) ->
    e.preventDefault()
    [_, threadID, replyID] = @href.match /(\d+)#p(\d+)/
    @textContent = "Loading No.#{replyID}..."
    a = @
    $.cache "//api.4chan.org#{@pathname}.json", -> ExpandComment.parse @, a, threadID, replyID

  parse: (req, a, threadID, replyID) ->
    _conf = Conf
    if req.status isnt 200
      a.textContent = "#{req.status} #{req.statusText}"
      return

    posts = JSON.parse(req.response).posts
    if spoilerRange = posts[0].custom_spoiler
      Build.spoilerRange[g.BOARD] = spoilerRange
    replyID = +replyID

    for post in posts
      break if post.no is replyID
    if post.no isnt replyID
      a.textContent = 'No.#{replyID} not found.'
      return

    bq = $.id "m#{replyID}"
    clone = bq.cloneNode false
    clone.innerHTML = post.com
    for quote in quotes = clone.getElementsByClassName 'quotelink'
      href = quote.getAttribute 'href'
      continue if href[0] is '/' # Cross-board quote
      quote.href = "res/#{href}" # Fix pathnames
    post =
      blockquote: clone
      threadID:   threadID
      quotes:     quotes
      backlinks:  []
    if _conf['Linkify']
      Linkify.node        post
    if _conf['Resurrect Quotes']
      Quotify.node        post
    if _conf['Quote Preview']
      QuotePreview.node   post
    if _conf['Quote Inline']
      QuoteInline.node    post
    if _conf['Indicate OP quote']
      QuoteOP.node        post
    if _conf['Indicate Cross-thread Quotes']
      QuoteCT.node        post
    if _conf['RemoveSpoilers']
      RemoveSpoilers.node post
    if _conf['Color user IDs']
      IDColor.node        post
    $.replace bq, clone
    Main.prettify clone

ExpandThread =
  init: ->
    for span in $$ '.summary'
      a = $.el 'a',
        textContent: "+ #{span.textContent}"
        className: 'summary desktop'
        href: 'javascript:;'
      $.on a, 'click', -> ExpandThread.toggle @parentNode
      $.replace span, a
    return

  toggle: (thread) ->
    url = "//api.4chan.org/#{g.BOARD}/res/#{thread.id[1..]}.json"
    a   = $ '.summary', thread

    switch a.textContent[0]
      when '+'
        a.textContent = a.textContent.replace '+', '× Loading...'
        $.cache url, -> ExpandThread.parse @, thread, a

      when 'X'
        a.textContent = a.textContent.replace '× Loading...', '+'
        $.cache.requests[url].abort()

      when '-'
        a.textContent = a.textContent.replace '-', '+'
        #goddamit moot
        num = switch g.BOARD
          when 'b', 'vg', 'q' then 3
          when 't' then 1
          else 5
        replies = $$ '.replyContainer', thread
        replies.splice replies.length - num, num
        for reply in replies
          $.rm reply
    return

  parse: (req, thread, a) ->
    if (status = req.status) isnt 200
      a.textContent = "#{status} #{req.statusText}"
      $.off a, 'click', ExpandThread.cb.toggle
      return

    a.textContent = a.textContent.replace '× Loading...', '-'

    posts = JSON.parse(req.response).posts
    if spoilerRange = posts[0].custom_spoiler
      Build.spoilerRange[g.BOARD] = spoilerRange

    replies  = posts[1..]
    threadID = thread.id[1..]
    nodes    = []
    for reply in replies
      post = Build.postFromObject reply, g.BOARD
      id   = reply.no
      link = $ 'a[title="Highlight this post"]', post
      link.href = "res/#{threadID}#p#{id}"
      link.nextSibling.href = "res/#{threadID}#q#{id}"
      nodes.push post
    # eat everything, then replace with fresh full posts
    for post in $$ '.summary ~ .replyContainer', a.parentNode
      $.rm post
    for backlink in $$ '.backlink', a.previousElementSibling
      # Keep backlinks from other threads.
      $.rm backlink unless $.id backlink.hash[1..]
    $.after a, nodes

ThreadHiding =
  init: ->
    @hiddenThreads = $.get "hiddenThreads/#{g.BOARD}/", {}
    ThreadHiding.sync()
    return if g.CATALOG
    for thread in $$ '.thread'
      a = $.el 'a',
        className: 'hide_thread_button'
        innerHTML: '<span>[<span></span>]</span>'
        href: 'javascript:;'
      $.on a, 'click', ->
        ThreadHiding.toggle @parentElement
      $.prepend thread, a

      if thread.id[1..] of @hiddenThreads
        ThreadHiding.hide thread
    return

  sync: ->
    hiddenThreadsCatalog = JSON.parse(localStorage.getItem "4chan-hide-t-#{g.BOARD}") or {}
    if g.CATALOG
      for id of @hiddenThreads
        hiddenThreadsCatalog[id] = true
      localStorage.setItem "4chan-hide-t-#{g.BOARD}", JSON.stringify hiddenThreadsCatalog
    else
      for id of hiddenThreadsCatalog
        unless id of @hiddenThreads
          @hiddenThreads[id] = Date.now()
      $.set "hiddenThreads/#{g.BOARD}/", @hiddenThreads

  toggle: (thread) ->
    id = thread.id[1..]
    if thread.hidden or /\bhidden_thread\b/.test thread.firstChild.className
      ThreadHiding.show thread
      delete ThreadHiding.hiddenThreads[id]
    else
      ThreadHiding.hide thread
      ThreadHiding.hiddenThreads[id] = Date.now()
    $.set "hiddenThreads/#{g.BOARD}/", ThreadHiding.hiddenThreads

  hide: (thread, show_stub=Conf['Show Stubs']) ->
    unless show_stub
      thread.hidden = true
      thread.nextElementSibling.hidden = true
      return

    return if /\bhidden_thread\b/.test thread.firstChild.className # already hidden once by the filter

    num     = 0
    if span = $ '.summary', thread
      num   = Number span.textContent.match /\d+/
    num    += $$('.opContainer ~ .replyContainer', thread).length
    text    = if num is 1 then '1 reply' else "#{num} replies"
    opInfo  = $('.desktop > .nameBlock', thread).textContent

    stub = $.el 'a',
      className: 'hidden_thread'
      innerHTML: '<span class=hide_thread_button>[ + ]</span>'
      href:      'javascript:;'
    $.on  stub, 'click', ->
      ThreadHiding.toggle @parentElement
    $.add stub, $.tn "#{opInfo} (#{text})"
    if Conf['Menu']
      menuButton = Menu.a.cloneNode true
      $.on menuButton, 'click', Menu.toggle
      $.add stub, [$.tn(' '), menuButton]
    $.prepend thread, stub

  show: (thread) ->
    if stub = $ '.hidden_thread', thread
      $.rm stub
    thread.hidden = false
    thread.nextElementSibling.hidden = false

ReplyHiding =
  init: ->
    Main.callbacks.push @node

  node: (post) ->
    return if post.isInlined or post.ID is post.threadID
    side = $ '.sideArrows', post.root
    side.className = 'hide_reply_button'
    side.innerHTML = '<a href="javascript:;"><span>[<span></span>]</span></a>'
    $.on side.firstChild, 'click', ->
      ReplyHiding.toggle button = @parentNode, root = button.parentNode, id = root.id[2..]

    if post.ID of g.hiddenReplies
      ReplyHiding.hide post.root

  toggle: (button, root, id) ->
    quotes = $$ ".quotelink[href$='#p#{id}'], .backlink[href$='#p#{id}']"
    if /\bstub\b/.test button.className
      ReplyHiding.show root
      $.rmClass root, 'hidden'
      for quote in quotes
        $.rmClass quote, 'filtered'
      delete g.hiddenReplies[id]
    else
      ReplyHiding.hide root
      for quote in quotes
        $.addClass quote, 'filtered'
      g.hiddenReplies[id] = Date.now()
    $.set "hiddenReplies/#{g.BOARD}/", g.hiddenReplies

  hide: (root, show_stub=Conf['Show Stubs']) ->
    side = $('.hide_reply_button', root) or $('.sideArrows', root)
    $.addClass side.parentNode, 'hidden'
    return if side.hidden # already hidden once by the filter
    side.hidden = true
    el = side.nextElementSibling
    el.hidden = true

    $.addClass root, 'hidden'

    return unless show_stub

    stub = $.el 'div',
      className: 'stub'
      innerHTML: '<a href="javascript:;"><span>[ + ]</span> </a>'
    a = stub.firstChild
    $.on  a, 'click', ->
      ReplyHiding.toggle button = @parentNode, root = button.parentNode, id = root.id[2..]
    $.add a, $.tn if Conf['Anonymize'] then 'Anonymous' else $('.desktop > .nameBlock', el).textContent
    if Conf['Menu']
      menuButton = Menu.a.cloneNode true
      $.on menuButton, 'click', Menu.toggle
      $.add stub, [$.tn(' '), menuButton]
    $.prepend root, stub

  show: (root) ->
    if stub = $ '.stub', root
      $.rm stub
    ($('.hide_reply_button', root) or $('.sideArrows', root)).hidden = false
    $('.post',       root).hidden = false

    $.rmClass root, 'hidden'

Menu =
  entries: []
  init: ->
    @a = $.el 'a',
      className: 'menu_button'
      href:      'javascript:;'
      innerHTML: '[<span></span>]'
    @el = $.el 'div',
      className: 'reply dialog'
      id:        'menu'
      tabIndex:  0
    $.on @el, 'click',   (e) -> e.stopPropagation()
    $.on @el, 'keydown', @keybinds

    # Doc here: https://github.com/MayhemYDG/4chan-x/wiki/Menu-API
    $.on d, 'AddMenuEntry', (e) -> Menu.addEntry e.detail

    Main.callbacks.push @node
  node: (post) ->
    if post.isInlined and !post.isCrosspost
      a = $ '.menu_button', post.el
    else
      a = Menu.a.cloneNode true
      # \u00A0 is nbsp
      $.add $('.postInfo', post.el), [$.tn('\u00A0'), a]
    $.on a, 'click', Menu.toggle

  toggle: (e) ->
    e.preventDefault()
    e.stopPropagation()

    if Menu.el.parentNode
      # Close if it's already opened.
      # Reopen if we clicked on another button.
      {lastOpener} = Menu
      Menu.close()
      return if lastOpener is @

    Menu.lastOpener = @
    post =
      if /\bhidden_thread\b/.test @parentNode.className
        $.x 'ancestor::div[parent::div[@class="board"]]/child::div[contains(@class,"opContainer")]', @
      else
        $.x 'ancestor::div[contains(@class,"postContainer")][1]', @
    Menu.open @, Main.preParse post
  open: (button, post) ->
    {el} = Menu
    # XXX GM/Scriptish require setAttribute
    el.setAttribute 'data-id', post.ID
    el.setAttribute 'data-rootid', post.root.id

    funk = (entry, parent) ->
      {children} = entry
      return unless entry.open post
      $.add parent, entry.el

      return unless children
      if subMenu = $ '.subMenu', entry.el
        # Reset sub menu, remove irrelevant entries.
        $.rm subMenu
      subMenu = $.el 'div',
        className: 'reply dialog subMenu'
      $.add entry.el, subMenu
      for child in children
        funk child, subMenu
      return
    for entry in Menu.entries
      funk entry, el

    Menu.focus $ '.entry', Menu.el
    $.on d, 'click', Menu.close
    $.add d.body, el

    # Position
    mRect = el.getBoundingClientRect()
    bRect = button.getBoundingClientRect()
    bTop  = d.documentElement.scrollTop  + d.body.scrollTop  + bRect.top
    bLeft = d.documentElement.scrollLeft + d.body.scrollLeft + bRect.left
    el.style.top =
      if bRect.top + bRect.height + mRect.height < d.documentElement.clientHeight
        bTop + bRect.height + 2 + 'px'
      else
        bTop - mRect.height - 2 + 'px'
    el.style.left =
      if bRect.left + mRect.width < d.documentElement.clientWidth
        bLeft + 'px'
      else
        bLeft + bRect.width - mRect.width + 'px'

    el.focus()
  close: ->
    {el} = Menu
    $.rm el
    for focused in $$ '.focused.entry', el
      $.rmClass focused, 'focused'
    el.innerHTML = null
    el.removeAttribute 'style'
    delete Menu.lastOpener
    delete Menu.focusedEntry
    $.off d, 'click', Menu.close

  keybinds: (e) ->
    el = Menu.focusedEntry

    switch Keybinds.keyCode(e) or e.keyCode
      when 'Esc'
        Menu.lastOpener.focus()
        Menu.close()
      when 13, 32 # 'Enter', 'Space'
        el.click()
      when 'Up'
        if next = el.previousElementSibling
          Menu.focus next
      when 'Down'
        if next = el.nextElementSibling
          Menu.focus next
      when 'Right'
        if (subMenu = $ '.subMenu', el) and next = subMenu.firstElementChild
          Menu.focus next
      when 'Left'
        if next = $.x 'parent::*[contains(@class,"subMenu")]/parent::*', el
          Menu.focus next
      else
        return

    e.preventDefault()
    e.stopPropagation()
  focus: (el) ->
    if focused = $.x 'parent::*/child::*[contains(@class,"focused")]', el
      $.rmClass focused, 'focused'
    for focused in $$ '.focused', el
      $.rmClass focused, 'focused'
    Menu.focusedEntry = el
    $.addClass el, 'focused'

  addEntry: (entry) ->
    funk = (entry) ->
      {el, children} = entry
      $.addClass el, 'entry'
      $.on el, 'focus mouseover', (e) ->
        e.stopPropagation()
        Menu.focus @
      return unless children
      $.addClass el, 'hasSubMenu'
      for child in children
        funk child
      return
    funk entry
    Menu.entries.push entry

Keybinds =
  init: ->
    for node in $$ '[accesskey]'
      node.removeAttribute 'accesskey'
    $.on d, 'keydown',  Keybinds.keydown

  keydown: (e) ->
    return unless key = Keybinds.keyCode e
    {target} = e
    if (nodeName = target.nodeName.toLowerCase()) is 'textarea' or nodeName is 'input'
      return unless (key is 'Esc') or (/\+/.test key)

    thread = Nav.getThread()
    _conf  = Conf
    switch key
      # QR & Options
      when _conf.openQR
        Keybinds.qr thread, true
      when _conf.openEmptyQR
        Keybinds.qr thread
      when _conf.openOptions
        Options.dialog() unless $.id 'overlay'
      when _conf.close
        if o = $.id 'overlay'
          Options.close.call o
        else if QR.el
          QR.close()
      when _conf.submit
        QR.submit() if QR.el and !QR.status()
      when _conf.hideQR
        if QR.el
          return QR.el.hidden = false if QR.el.hidden
          QR.autohide.click()
        else QR.open()
      when _conf.toggleCatalog
        CatalogLinks.toggle()
      when _conf.spoiler
        return unless ($ '[name=spoiler]') and nodeName is 'textarea'
        Keybinds.tags 'spoiler', target
      when _conf.math
        return unless g.BOARD is (!! $ 'script[src^="//boards.4chan.org/jsMath/"]', d.head) and nodeName is 'textarea'
        Keybinds.tags 'math', target
      when _conf.eqn
        return unless g.BOARD is (!! $ 'script[src^="//boards.4chan.org/jsMath/"]', d.head) and nodeName is 'textarea'
        Keybinds.tags 'eqn', target
      when _conf.code
        return unless g.BOARD is Main.hasCodeTags and nodeName is 'textarea'
        Keybinds.tags 'code', target
      when _conf.sageru
        $("[name=email]", QR.el).value = "sage"
        QR.selected.email = "sage"
      # Thread related
      when _conf.watch
        Watcher.toggle thread
      when _conf.update
        Updater.update()
      when _conf.unreadCountTo0
        Unread.replies = []
        Unread.update true
      # Images
      when _conf.expandImage
        Keybinds.img thread
      when _conf.expandAllImages
        Keybinds.img thread, true
      # Board Navigation
      when _conf.zero
        window.location = "/#{g.BOARD}/0#delform"
      when _conf.nextPage
        if form = $ '.next form'
          window.location = form.action
       when _conf.previousPage
        if form = $ '.prev form'
          window.location = form.action
      # Thread Navigation
      when _conf.nextThread
        return if g.REPLY
        Nav.scroll +1
      when _conf.previousThread
        return if g.REPLY
        Nav.scroll -1
      when _conf.expandThread
        ExpandThread.toggle thread
      when _conf.openThread
        Keybinds.open thread
      when _conf.openThreadTab
        Keybinds.open thread, true
      # Reply Navigation
      when _conf.nextReply
        Keybinds.hl +1, thread
      when _conf.previousReply
        Keybinds.hl -1, thread
      when _conf.hide
        ThreadHiding.toggle thread if /\bthread\b/.test thread.className
      else
        return
    e.preventDefault()

  keyCode: (e) ->
    key = if [48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90].contains(kc = e.keyCode)
      c = String.fromCharCode kc
      if e.shiftKey then c else c.toLowerCase()
    else (switch kc
      when 8
        ''
      when 13
        'Enter'
      when 27
        'Esc'
      when 37
        'Left'
      when 38
        'Up'
      when 39
        'Right'
      when 40
        'Down'
      else
        null)
    if key
      if e.altKey  then key = 'alt+'  + key
      if e.ctrlKey then key = 'ctrl+' + key
      if e.metaKey then key = 'meta+' + key
    key

  tags: (tag, ta) ->
    value    = ta.value
    selStart = ta.selectionStart
    selEnd   = ta.selectionEnd

    ta.value =
      value[...selStart] +
      "[#{tag}]" + value[selStart...selEnd] + "[/#{tag}]" +
      value[selEnd..]

    range = "[#{tag}]".length + selEnd
    # Move the caret to the end of the selection.
    ta.setSelectionRange range, range

    # Fire the 'input' event
    $.event ta, new Event 'input'

  img: (thread, all) ->
    if all
      $.id('imageExpand').click()
    else
      thumb = $ 'img[data-md5]', $('.post.highlight', thread) or thread
      ImageExpand.toggle thumb.parentNode

  qr: (thread, quote) ->
    if quote
      QR.quote.call $ 'a[title="Quote this post"]', $('.post.highlight', thread) or thread
    else
      QR.open()
    $('textarea', QR.el).focus()

  open: (thread, tab) ->
    return if g.REPLY
    id = thread.id[1..]
    url = "//boards.4chan.org/#{g.BOARD}/res/#{id}"
    if tab
      $.open url
    else
      location.href = url

  hl: (delta, thread) ->
    if post = $ '.reply.highlight', thread
      $.rmClass post, 'highlight'
      rect = post.getBoundingClientRect()
      if rect.bottom >= 0 and rect.top <= d.documentElement.clientHeight # We're at least partially visible
        axis = if delta is +1 then 'following' else 'preceding'
        next = $.x axis + '::div[contains(@class,"post reply")][1]', post
        return unless next
        return unless g.REPLY or $.x('ancestor::div[parent::div[@class="board"]]', next) is thread
        rect = next.getBoundingClientRect()
        if rect.top < 0 or rect.bottom > d.documentElement.clientHeight
          next.scrollIntoView delta is -1
        @focus next
        return

    replies = $$ '.reply', thread
    replies.reverse() if delta is -1
    for reply in replies
      rect = reply.getBoundingClientRect()
      if delta is +1 and rect.top >= 0 or delta is -1 and rect.bottom <= d.documentElement.clientHeight
        @focus reply
        return

  focus: (post) ->
    $.addClass post, 'highlight'
    post.focus()

Nav =
  # ▲ ▼
  init: ->
    span = $.el 'span'
      id: 'navlinks'
    prev = $.el 'a'
      href: 'javascript:;'
    next = $.el 'a'
      href: 'javascript:;'

    $.on prev, 'click', @prev
    $.on next, 'click', @next

    $.add span, [prev, next]
    $.add d.body, span

  prev: ->
    if g.REPLY
      window.scrollTo 0, 0
    else
      Nav.scroll -1

  next: ->
    if g.REPLY
      window.scrollTo 0, d.body.scrollHeight
    else
      Nav.scroll +1

  getThread: (full) ->
    Nav.threads = $$ '.thread:not(.hidden)'
    for thread, i in Nav.threads
      rect = thread.getBoundingClientRect()
      {bottom} = rect
      if bottom > 0 # We have not scrolled past
        if full
          return [thread, i, rect]
        return thread
    return $ '.board'

  scroll: (delta) ->
    [thread, i, rect] = Nav.getThread true
    {top} = rect

    # unless we're not at the beginning of the current thread
    # (and thus wanting to move to beginning)
    # or we're above the first thread and don't want to skip it
    unless (delta is -1 and Math.ceil(top) < 0) or (delta is +1 and top > 1)
      i += delta

    {top} = Nav.threads[i]?.getBoundingClientRect()
    window.scrollBy 0, top

BanChecker =
  init: ->
    @now = Date.now()
    return if not Conf['Check for Bans constantly'] and reason = $.get 'isBanned'
      BanChecker.prepend(reason)
    else if Conf['Check for Bans constantly'] or $.get('lastBanCheck', 0) < @now - 6 * $.HOUR
      BanChecker.load()

  load: ->
    @url = 'https://www.4chan.org/banned'
    $.ajax @url,
      onloadend: ->
        if @status is 200 or 304
          $.set 'lastBanCheck', BanChecker.now unless Conf['Check for Bans constantly']
          doc = d.implementation.createHTMLDocument ''
          doc.documentElement.innerHTML = @response
          if /no entry in our database/i.test (msg = $('.boxcontent', doc).textContent.trim())
            if $.get 'isBanned', false
              $.delete 'isBanned'
              $.rm BanChecker.el
              delete BanChecker.el
            return
          $.set 'isBanned', reason =
            if /This ban will not expire/i.test msg
              'You are permabanned.'
            else
              'You are banned.'
          BanChecker.prepend(reason)

  prepend: (reason) ->
    unless BanChecker.el
      Banchecker.el = el = $.el 'h2'
        id:    'banmessage'
        class: 'warning'
        innerHTML: "
          <span>#{reason}</span>
          <a href=#{BanChecker.url} title='Click to find out why.' target=_blank>Click to find out why.</a>"
        title:  'Click to recheck.'
        $.on el.lastChild, 'click', ->
          $.delete 'lastBanCheck' unless Conf['Check for Bans constantly']
          $.delete 'isBanned'
          @parentNode.style.opacity = '.5'
          BanChecker.load()
      $.before $.id('delform'), el
    else
      Banchecker.el.firstChild.textContent = reason


Updater =
  init: ->
    # Setup basic HTML layout.
    html = '<div class=move><span id=count></span> <span id=timer></span></div>'

    # Gather possible toggle configuration variables from Config object
    {checkbox} = Config.updater

    # And create fields for them.
    for name of checkbox
      title = checkbox[name][1]

      # Gather user values.
      checked = if Conf[name] then 'checked' else ''

      # And create HTML for each checkbox.
      html += "<div><label title='#{title}'>#{name}<input name='#{name}' type=checkbox #{checked}></label></div>"

    checked = if Conf['Auto Update'] then 'checked' else ''

    # Per thread auto-update and global or per board update frequency.
    html += "
      <div><label title='Controls whether *this* thread automatically updates or not'>Auto Update This<input name='Auto Update This' type=checkbox #{checked}></label></div>
      <div><label>Interval (s)<input type=number name=Interval#{if Conf['Interval per board'] then "_" + g.BOARD else ''} class=field min=1></label></div>
      <div><label>BGInterval<input type=number name=BGInterval#{if Conf['Interval per board'] then "_" + g.BOARD else ''} class=field min=1></label></div>
      <div><input value='Update Now' type=button name='Update Now'></div>"

    # Create a moveable dialog. See UI.dialog for more information.
    dialog = UI.dialog 'updater', 'bottom: 0; right: 0;', html

    # Point updater variables at HTML elements for ease of access.
    @count  = $ '#count', dialog
    @timer  = $ '#timer', dialog
    @thread = $.id "t#{g.THREAD_ID}"
    @save   = []

    @checkPostCount = 0
    @unsuccessfulFetchCount = 0
    @lastModified = '0'

    # Add event listeners to updater dialogs.
    for input in $$ 'input', dialog
      if input.type is 'checkbox'
        # Change localstorage value on click.
        $.on input, 'click', $.cb.checked
      switch input.name
        when 'Scroll BG'
          $.on input, 'click', @cb.scrollBG
          @cb.scrollBG.call input
        when 'Verbose'
          $.on input, 'click', @cb.verbose
          @cb.verbose.call input
        when 'Auto Update This'
          $.on input, 'click', @cb.autoUpdate
          @cb.autoUpdate.call input
        when 'Interval', 'BGInterval', "Interval_" + g.BOARD, "BGInterval_" + g.BOARD
          input.value = Conf[input.name]
          $.on input, 'change', @cb.interval
          @cb.interval.call input
        when 'Update Now'
          $.on input, 'click', @update

    # Applies fake checkboxes.
    Style.rice dialog

    $.add d.body, dialog

    # Check for new posts on post.
    $.on d, 'QRPostSuccessful', @cb.post

    $.on d, 'visibilitychange ovisibilitychange mozvisibilitychange webkitvisibilitychange', @cb.visibility

  ###
  beep1.wav
  http://freesound.org/people/pierrecartoons1979/sounds/90112

  This work is licensed under the Attribution Noncommercial License.
  http://creativecommons.org/licenses/by-nc/3.0/
  ###

  audio:
    $.el 'audio'
      src: 'data:audio/wav;base64,UklGRjQDAABXQVZFZm10IBAAAAABAAEAgD4AAIA+AAABAAgAc21wbDwAAABBAAADAAAAAAAAAAA8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABkYXRhzAIAAGMms8em0tleMV4zIpLVo8nhfSlcPR102Ki+5JspVEkdVtKzs+K1NEhUIT7DwKrcy0g6WygsrM2k1NpiLl0zIY/WpMrjgCdbPhxw2Kq+5Z4qUkkdU9K1s+K5NkVTITzBwqnczko3WikrqM+l1NxlLF0zIIvXpsnjgydZPhxs2ay95aIrUEkdUdC3suK8N0NUIjq+xKrcz002WioppdGm091pK1w0IIjYp8jkhydXPxxq2K295aUrTkoeTs65suK+OUFUIzi7xqrb0VA0WSoootKm0t5tKlo1H4TYqMfkiydWQBxm16+85actTEseS8y7seHAPD9TIza5yKra01QyWSson9On0d5wKVk2H4DYqcfkjidUQB1j1rG75KsvSkseScu8seDCPz1TJDW2yara1FYxWSwnm9Sn0N9zKVg2H33ZqsXkkihSQR1g1bK65K0wSEsfR8i+seDEQTxUJTOzy6rY1VowWC0mmNWoz993KVc3H3rYq8TklSlRQh1d1LS647AyR0wgRMbAsN/GRDpTJTKwzKrX1l4vVy4lldWpzt97KVY4IXbUr8LZljVPRCxhw7W3z6ZISkw1VK+4sMWvXEhSPk6buay9sm5JVkZNiLWqtrJ+TldNTnquqbCwilZXU1BwpKirrpNgWFhTaZmnpquZbFlbVmWOpaOonHZcXlljhaGhpZ1+YWBdYn2cn6GdhmdhYGN3lp2enIttY2Jjco+bnJuOdGZlZXCImJqakHpoZ2Zug5WYmZJ/bGlobX6RlpeSg3BqaW16jZSVkoZ0bGtteImSk5KIeG5tbnaFkJKRinxxbm91gY2QkIt/c3BwdH6Kj4+LgnZxcXR8iI2OjIR5c3J0e4WLjYuFe3VzdHmCioyLhn52dHR5gIiKioeAeHV1eH+GiYqHgXp2dnh9hIiJh4J8eHd4fIKHiIeDfXl4eHyBhoeHhH96eHmA'

  cb:
    post: ->
      return unless Conf['Auto Update This']
      Updater.unsuccessfulFetchCount = 0
      setTimeout Updater.update, 500
    checkpost: (status) ->
      unless status is 404 and Updater.save.contains(Updater.postID) and Updater.checkPostCount >= 10
        return ( -> setTimeout Updater.update, @ ).call ++Updater.checkPostCount * 500
      Updater.save = []
      Updater.checkPostCount = 0
      delete Updater.postID
    visibility: ->
      return if $.hidden()
      # Reset the counter when we focus this tab.
      Updater.unsuccessfulFetchCount = 0
      if Conf['Interval per board']
        if Updater.timer.textContent < -Conf['Interval_' + g.BOARD]
          Updater.set 'timer', -Updater.getInterval()
      else
        if Updater.timer.textContent < -Conf['Interval']
          Updater.set 'timer', -Updater.getInterval()
    interval: ->
      val = parseInt @value, 10
      @value = if val > 0 then val else 30
      $.cb.value.call @
      Updater.set 'timer', -Updater.getInterval()
    verbose: ->
      if Conf['Verbose']
        Updater.set 'count', '+0'
        Updater.timer.hidden = false
      else
        Updater.set 'count', '+0'
        Updater.count.className = ''
        Updater.timer.hidden = true
    autoUpdate: ->
      if Conf['Auto Update This'] = @checked
        Updater.timeoutID = setTimeout Updater.timeout, 1000
      else
        clearTimeout Updater.timeoutID
    scrollBG: ->
      Updater.scrollBG =
        if @checked
          -> true
        else
          -> ! $.hidden()
    load: ->
      switch @status
        when 404
          Updater.set 'timer', ''
          Updater.set 'count', 404
          Updater.count.className = 'warning'
          clearTimeout Updater.timeoutID
          g.dead = true
          if Conf['Unread Count']
            Unread.title = Unread.title.match(/^.+-/)[0] + ' 404'
          else
            d.title = d.title.match(/^.+-/)[0] + ' 404'
          Unread.update true
          QR.abort()
        # XXX 304 -> 0 in Opera
        when 0, 304
          ###
          Status Code 304: Not modified
          By sending the `If-Modified-Since` header we get a proper status code, and no response.
          This saves bandwidth for both the user and the servers and avoid unnecessary computation.
          ###

          Updater.unsuccessfulFetchCount++
          Updater.set 'timer', -Updater.getInterval()
          if Conf['Verbose']
            Updater.set 'count', '+0'
            Updater.count.className = null
        when 200
          Updater.lastModified = @getResponseHeader 'Last-Modified'
          Updater.cb.update JSON.parse(@response).posts
          Updater.set 'timer', -Updater.getInterval()
        else
          Updater.unsuccessfulFetchCount++
          Updater.set 'timer', -Updater.getInterval()
          if Conf['Verbose']
            Updater.set 'count', @statusText
            Updater.count.className = 'warning'
      if Updater.postID
        Updater.cb.checkpost @status
      delete Updater.request
      Updater.checkPostCount = 0
      Updater.save = []
      delete Updater.postID
    update: (posts) ->
      if spoilerRange = posts[0].custom_spoiler
        Build.spoilerRange[g.BOARD] = spoilerRange

      lastPost = Updater.thread.lastElementChild
      id = +lastPost.id[2..]
      nodes = for post in posts.reverse()
        break if post.no <= id # Make sure to not insert older posts.
        Updater.save.push post.no if Updater.postID
        Build.postFromObject post, g.BOARD

      count = nodes.length
      if Conf['Verbose']
        Updater.set 'count', "+#{count}"
        Updater.count.className = if count then 'new' else null

      if count
        if Conf['Beep'] and $.hidden() and (Unread.replies.length is 0)
          Updater.audio.play()
        Updater.unsuccessfulFetchCount = 0
      else
        Updater.unsuccessfulFetchCount++
        return

      scroll = Conf['Scrolling'] and Updater.scrollBG() and
        lastPost.getBoundingClientRect().bottom - d.documentElement.clientHeight < 25
      $.add Updater.thread, nodes.reverse()
      if scroll and nodes?
        nodes[0].scrollIntoView()

  set: (name, text) ->
    el = Updater[name]
    if node = el.firstChild
      # Prevent the creation of a new DOM Node
      # by setting the text node's data.
      node.data = text
    else
      el.textContent = text

  getInput: (input) ->
    while (i = input.length) < 10
      input[i] = input[i - 1]
    parseInt(number, 10) for number in input

  getInterval: ->
    string = "Interval" + (if Conf['Interval per board'] then "_#{g.BOARD}" else "")
    increaseString = "updateIncrease"
    if $.hidden()
      string = "BG#{string}"
      increaseString += "B"
    i  = +Conf[string]
    j = if (count = @unsuccessfulFetchCount) > 9 then 9 else count
    return (
      if Conf['Optional Increase']
        (if i > increase = Updater.getInput(Conf[increaseString].split ',')[j] then i else increase)
      else
        i
    )

  timeout: ->
    Updater.timeoutID = setTimeout Updater.timeout, 1000
    n = 1 + parseInt Updater.timer.firstChild.data, 10

    if n is 0
      Updater.update()
    else if n >= Updater.getInterval()
      Updater.unsuccessfulFetchCount++
      Updater.set 'count', 'Retry'
      Updater.count.className = null
      Updater.update()
    else
      Updater.set 'timer', n

  update: ->
    Updater.set 'timer', 0
    {request} = Updater
    if request
      # Don't reset the counter when aborting.
      request.onloadend = null
      request.abort()
    url = "//api.4chan.org/#{g.BOARD}/res/#{g.THREAD_ID}.json"
    Updater.request = $.ajax url, onloadend: Updater.cb.load,
      headers: 'If-Modified-Since': Updater.lastModified

Watcher =
  init: ->
    html = '<div class=move>Thread Watcher</div>'
    @dialog = UI.dialog 'watcher', 'top: 50px; left: 0px;', html
    $.add d.body, @dialog

    #add watch buttons
    for input in $$ '.op input'
      favicon = $.el 'img',
        className: 'favicon'
      $.on favicon, 'click', @cb.toggle
      $.before input, favicon

    if g.THREAD_ID is $.get 'autoWatch', 0
      @watch g.THREAD_ID
      $.delete 'autoWatch'
    else
      #populate watcher, display watch buttons
      @refresh()

    $.on d, 'QRPostSuccessful', @cb.post
    $.sync 'watched', @refresh

  refresh: (watched) ->
    watched or= $.get 'watched', {}
    nodes = []
    for board of watched
      for id, props of watched[board]
        x = $.el 'a',
          textContent: '×'
          href: 'javascript:;'
        $.on x, 'click', Watcher.cb.x
        link = $.el 'a', props
        link.title = link.textContent

        div = $.el 'div'
        $.add div, [x, $.tn(' '), link]
        nodes.push div

    for div in $$ 'div:not(.move)', Watcher.dialog
      $.rm div
    $.add Watcher.dialog, nodes

    watchedBoard = watched[g.BOARD] or {}
    for favicon in $$ '.favicon'
      id = favicon.nextSibling.name
      if id of watchedBoard
        favicon.src = Favicon.default
      else
        favicon.src = Favicon.empty
    return

  cb:
    toggle: ->
      Watcher.toggle @parentNode
    x: ->
      thread = @nextElementSibling.pathname.split '/'
      Watcher.unwatch thread[3], thread[1]
    post: (e) ->
      {postID, threadID} = e.detail
      if threadID is '0'
        if Conf['Auto Watch']
          $.set 'autoWatch', postID
      else if Conf['Auto Watch Reply']
        Watcher.watch threadID

  toggle: (thread) ->
    id = $('.favicon + input', thread).name
    Watcher.watch(id) or Watcher.unwatch id, g.BOARD

  unwatch: (id, board) ->
    watched = $.get 'watched', {}
    delete watched[board][id]
    $.set 'watched', watched
    Watcher.refresh()

  watch: (id) ->
    thread = $.id "t#{id}"
    return false if $('.favicon', thread).src is Favicon.default

    watched = $.get 'watched', {}
    watched[g.BOARD] or= {}
    watched[g.BOARD][id] =
      href: "/#{g.BOARD}/res/#{id}"
      textContent: Get.title thread
    $.set 'watched', watched
    Watcher.refresh()
    true

Anonymize =
  init: ->
    Main.callbacks.push @node
  node: (post) ->
    return if post.isInlined and not post.isCrosspost
    name = $ '.postInfo .name', post.el
    name.textContent = 'Anonymous'
    if (trip = name.nextElementSibling) and trip.className is 'postertrip'
      $.rm trip
    if (parent = name.parentNode).className is 'useremail' and not /^mailto:sage$/i.test parent.href
      $.replace parent, name

Sauce =
  init: ->
    return if g.BOARD is 'f'
    @links = []
    for link in Conf['sauces'].split '\n'
      continue if link[0] is '#'
      # XXX .trim() is there to fix Opera reading two different line breaks.
      @links.push @createSauceLink link.trim()
    return unless @links.length
    Main.callbacks.push @node

  createSauceLink: (link) ->
    link = link.replace /(\$\d)/g, (parameter) ->
      switch parameter
        when '$1'
          "' + (isArchived ? img.firstChild.src : 'http://thumbs.4chan.org' + img.pathname.replace(/src(\\/\\d+).+$/, 'thumb$1s.jpg')) + '"
        when '$2'
          "' + img.href + '"
        when '$3'
          "' + encodeURIComponent(img.firstChild.dataset.md5) + '"
        when '$4'
          g.BOARD
        else
          parameter
    domain = if m = link.match(/;text:(.+)$/) then m[1] else link.match(/(\w+)\.\w+\//)[1]
    href = link.replace /;text:.+$/, ''
    href = Function 'img', 'isArchived', "return '#{href}'"
    el = $.el 'a',
      target: '_blank'
      textContent: domain
    (img, isArchived) ->
      a = el.cloneNode true
      a.href = href img, isArchived
      a

  node: (post) ->
    {img} = post
    return if post.isInlined and not post.isCrosspost or not img
    img   = img.parentNode
    nodes = []
    for link in Sauce.links
      # \u00A0 is nbsp
      nodes.push $.tn('\u00A0'), link img, post.isArchived
    $.add post.fileInfo, nodes

RevealSpoilers =
  init: ->
    Main.callbacks.push @node
  node: (post) ->
    {img} = post
    if not (img and /^Spoiler/.test img.alt) or post.isInlined and not post.isCrosspost or post.isArchived
      return
    img.removeAttribute 'style'
    # revealed spoilers do not have height/width set, this fixes auto-gifs dimensions.
    s = img.style
    s.maxHeight = s.maxWidth = if /\bop\b/.test post.class then '250px' else '125px'
    img.src = "//thumbs.4chan.org#{img.parentNode.pathname.replace /src(\/\d+).+$/, 'thumb$1s.jpg'}"

RemoveSpoilers =
  init: ->
    Main.callbacks.push @node

  node: (post) ->
    spoilers = $$ 's', post.el
    for spoiler in spoilers
      $.replace spoiler, $.tn spoiler.textContent
    return

Time =
  init: ->
    Time.foo()
    Main.callbacks.push @node
  node: (post) ->
    return if post.isInlined and not post.isCrosspost
    node             = $ '.postInfo > .dateTime', post.el
    Time.date        = new Date node.dataset.utc * 1000
    node.textContent = Time.funk Time
  foo: ->
    code = Conf['time'].replace /%([A-Za-z])/g, (s, c) ->
      if c of Time.formatters
        "' + Time.formatters.#{c}() + '"
      else
        s
    Time.funk = Function 'Time', "return '#{code}'"
  day: [
    'Sunday'
    'Monday'
    'Tuesday'
    'Wednesday'
    'Thursday'
    'Friday'
    'Saturday'
  ]
  month: [
    'January'
    'February'
    'March'
    'April'
    'May'
    'June'
    'July'
    'August'
    'September'
    'October'
    'November'
    'December'
  ]
  zeroPad: (n) -> if n < 10 then '0' + n else n
  formatters:
    a: -> Time.day[Time.date.getDay()][...3]
    A: -> Time.day[Time.date.getDay()]
    b: -> Time.month[Time.date.getMonth()][...3]
    B: -> Time.month[Time.date.getMonth()]
    d: -> Time.zeroPad Time.date.getDate()
    e: -> Time.date.getDate()
    H: -> Time.zeroPad Time.date.getHours()
    I: -> Time.zeroPad Time.date.getHours() % 12 or 12
    k: -> Time.date.getHours()
    l: -> Time.date.getHours() % 12 or 12
    m: -> Time.zeroPad Time.date.getMonth() + 1
    M: -> Time.zeroPad Time.date.getMinutes()
    p: -> if Time.date.getHours() < 12 then 'AM' else 'PM'
    P: -> if Time.date.getHours() < 12 then 'am' else 'pm'
    S: -> Time.zeroPad Time.date.getSeconds()
    y: -> Time.date.getFullYear() - 2000

FileInfo =
  init: ->
    return if g.BOARD is 'f'
    @setFormats()
    Main.callbacks.push @node
  node: (post) ->
    return if post.isInlined and not post.isCrosspost or not post.fileInfo
    node = post.fileInfo.firstElementChild
    alt  = post.img.alt
    filename = $('span', node)?.title or node.title
    FileInfo.data =
      link:       post.img.parentNode.href
      spoiler:    /^Spoiler/.test alt
      size:       alt.match(/\d+\.?\d*/)[0]
      unit:       alt.match(/\w+$/)[0]
      resolution: node.textContent.match(/\d+x\d+|PDF/)[0]
      fullname:   filename
      shortname:  Build.shortFilename filename, post.ID is post.threadID
    # XXX GM/Scriptish
    node.setAttribute 'data-filename', filename
    node.innerHTML = FileInfo.funk FileInfo
  setFormats: ->
    code = Conf['fileInfo'].replace /%(.)/g, (s, c) ->
      if c of FileInfo.formatters
        "' + f.formatters.#{c}() + '"
      else
        s
    @funk = Function 'f', "return '#{code}'"
  convertUnit: (unitT) ->
    size  = @data.size
    unitF = @data.unit
    if unitF isnt unitT
      units = ['B', 'KB', 'MB']
      i     = units.indexOf(unitF) - units.indexOf unitT
      unitT = 'Bytes' if unitT is 'B'
      if i > 0
        size *= 1024 while i-- > 0
      else if i < 0
        size /= 1024 while i++ < 0
      if size < 1 and size.toString().length > size.toFixed(2).length
        size = size.toFixed 2
    "#{size} #{unitT}"
  formatters:
    t: -> FileInfo.data.link.match(/\d+\..+$/)[0]
    T: -> "<a href=#{FileInfo.data.link} target=_blank>#{@t()}</a>"
    l: -> "<a href=#{FileInfo.data.link} target=_blank>#{@n()}</a>"
    L: -> "<a href=#{FileInfo.data.link} target=_blank>#{@N()}</a>"
    n: ->
      if FileInfo.data.fullname is FileInfo.data.shortname
        FileInfo.data.fullname
      else
        "<span class=fntrunc>#{FileInfo.data.shortname}</span><span class=fnfull>#{FileInfo.data.fullname}</span>"
    N: -> FileInfo.data.fullname
    p: -> if FileInfo.data.spoiler then 'Spoiler, ' else ''
    s: -> "#{FileInfo.data.size} #{FileInfo.data.unit}"
    B: -> FileInfo.convertUnit 'B'
    K: -> FileInfo.convertUnit 'KB'
    M: -> FileInfo.convertUnit 'MB'
    r: -> FileInfo.data.resolution

Get =
  post: (board, threadID, postID, root, cb) ->
    if board is g.BOARD and post = $.id "pc#{postID}"
      $.add root, Get.cleanPost post.cloneNode true
      return

    root.innerHTML = "<div class=post>Loading post No.#{postID}...</div>"
    if threadID
      $.cache "//api.4chan.org/#{board}/res/#{threadID}.json", ->
        Get.parsePost @, board, threadID, postID, root, cb
    else if url = Redirect.post board, postID
      $.cache url, ->
        Get.parseArchivedPost @, board, postID, root, cb
  parsePost: (req, board, threadID, postID, root, cb) ->
    {status} = req
    if status isnt 200
      # The thread can die by the time we check a quote.
      if url = Redirect.post board, postID
        $.cache url, ->
          Get.parseArchivedPost @, board, postID, root, cb
      else
        $.addClass root, 'warning'
        root.innerHTML =
          if status is 404
            "<div class=post>Thread No.#{threadID} 404'd.</div>"
          else
            "<div class=post>Error #{req.status}: #{req.statusText}.</div>"
      return

    posts = JSON.parse(req.response).posts
    if spoilerRange = posts[0].custom_spoiler
      Build.spoilerRange[board] = spoilerRange
    postID = +postID
    for post in posts
      break if post.no is postID # we found it!
      if post.no > postID
        # The post can be deleted by the time we check a quote.
        if url = Redirect.post board, postID
          $.cache url, ->
            Get.parseArchivedPost @, board, postID, root, cb
        else
          $.addClass root, 'warning'
          root.textContent = "Post No.#{postID} was not found."
        return

    $.replace root.firstChild, Get.cleanPost Build.postFromObject post, board
    cb() if cb
  parseArchivedPost: (req, board, postID, root, cb) ->
    data = JSON.parse req.response
    if data.error
      $.addClass root, 'warning'
      root.textContent = data.error
      return

    # convert comment to html
    bq = $.el 'blockquote', textContent: data.comment # set this first to convert text to HTML entities
    # https://github.com/eksopl/fuuka/blob/master/Board/Yotsuba.pm#L413-452
    # https://github.com/eksopl/asagi/blob/master/src/main/java/net/easymodo/asagi/Yotsuba.java#L109-138
    bq.innerHTML = bq.innerHTML.replace ///
      \n
      | \[/?b\]
      | \[/?spoiler\]
      | \[/?code\]
      | \[/?moot\]
      | \[/?banned\]
      ///g, (text) ->
        switch text
          when '\n'
            '<br>'
          when '[b]'
            '<b>'
          when '[/b]'
            '</b>'
          when '[spoiler]'
            '<s>'
          when '[/spoiler]'
            '</s>'
          when '[code]'
            '<pre class=prettyprint>'
          when '[/code]'
            '</pre>'
          when '[moot]'
            '<div style="padding:5px;margin-left:.5em;border-color:#faa;border:2px dashed rgba(255,0,0,.1);border-radius:2px">'
          when '[/moot]'
            '</div>'
          when '[banned]'
            '<b style="color: red;">'
          when '[/banned]'
            '</b>'
    # greentext
    comment = bq.innerHTML.replace /(^|>)(&gt;[^<$]*)(<|$)/g, '$1<span class=quote>$2</span>$3'

    o =
      # id
      postID:   postID
      threadID: data.thread_num
      board:    board
      # info
      name:     data.name_processed
      capcode:  switch data.capcode
        when 'M' then 'mod'
        when 'A' then 'admin'
        when 'D' then 'developer'
      tripcode: data.trip
      uniqueID: data.poster_hash
      email:    if data.email then encodeURI data.email.replace /&quot;/g, '"' else ''
      subject:  data.title_processed
      flagCode: data.poster_country
      flagName: data.poster_country_name_processed
      date:     data.fourchan_date
      dateUTC:  data.timestamp
      comment:  comment
      # file
    if data.media?.media_filename
      o.file =
        name:      data.media.media_filename_processed
        timestamp: data.media.media_orig
        url:       data.media.media_link or data.media.remote_media_link
        height:    data.media.media_h
        width:     data.media.media_w
        MD5:       data.media.media_hash
        size:      data.media.media_size
        turl:      data.media.thumb_link or "//thumbs.4chan.org/#{board}/thumb/#{data.media.preview_orig}"
        theight:   data.media.preview_h
        twidth:    data.media.preview_w
        isSpoiler: data.media.spoiler is '1'

    $.replace root.firstChild, Get.cleanPost Build.post o, true
    cb() if cb
  cleanPost: (root) ->
    post = $ '.post', root
    for child in Array::slice.call root.childNodes
      $.rm child unless child is post

    # Remove inlined posts inside of this post.
    for inline  in $$ '.inline',  post
      $.rm inline
    for inlined in $$ '.inlined', post
      $.rmClass inlined, 'inlined'

    # Don't mess with other features
    now = Date.now()
    els = $$ '[id]', root
    els.push root
    for el in els
      el.id = "#{now}_#{el.id}"

    $.rmClass root, 'forwarded'
    $.rmClass root, 'qphl' # op
    $.rmClass post, 'highlight'
    $.rmClass post, 'qphl' # reply
    root.hidden = post.hidden = false

    root
  title: (thread) ->
    op = $ '.op', thread
    el = $ '.postInfo .subject', op
    unless el.textContent
      el = $ 'blockquote', op
      unless el.textContent
        el = $ '.nameBlock', op
    span = $.el 'span', innerHTML: el.innerHTML.replace /<br>/g, ' '
    "/#{g.BOARD}/ - #{span.textContent.trim()}"

Build =
  spoilerRange: {}
  shortFilename: (filename, isOP) ->
    # FILENAME SHORTENING SCIENCE:
    # OPs have a +10 characters threshold.
    # The file extension is not taken into account.
    threshold = if isOP then 40 else 30
    if filename.length - 4 > threshold
      "#{filename[...threshold - 5]}(...).#{filename[-3..]}"
    else
      filename
  postFromObject: (data, board) ->
    o =
      # id
      postID:   data.no
      threadID: data.resto or data.no
      board:    board
      # info
      name:     data.name
      capcode:  data.capcode
      tripcode: data.trip
      uniqueID: data.id
      email:    if data.email then encodeURI data.email.replace /&quot;/g, '"' else ''
      subject:  data.sub
      flagCode: data.country
      flagName: data.country_name
      date:     data.now
      dateUTC:  data.time
      comment:  data.com
      # thread status
      isSticky: !!data.sticky
      isClosed: !!data.closed
    # file
    if data.ext or data.filedeleted
      o.file =
        name:      data.filename + data.ext
        timestamp: "#{data.tim}#{data.ext}"
        url:       "//images.4chan.org/#{board}/src/#{data.tim}#{data.ext}"
        height:    data.h
        width:     data.w
        MD5:       data.md5
        size:      data.fsize
        turl:      "//thumbs.4chan.org/#{board}/thumb/#{data.tim}s.jpg"
        theight:   data.tn_h
        twidth:    data.tn_w
        isSpoiler: !!data.spoiler
        isDeleted: !!data.filedeleted
    Build.post o
  post: (o, isArchived) ->
    ###
    This function contains code from 4chan-JS (https://github.com/4chan/4chan-JS).
    @license: https://github.com/4chan/4chan-JS/blob/master/LICENSE
    ###
    {
      postID, threadID, board
      name, capcode, tripcode, uniqueID, email, subject, flagCode, flagName, date, dateUTC
      isSticky, isClosed
      comment
      file
    } = o
    isOP = postID is threadID

    staticPath = '//static.4chan.org'

    if email
      emailStart = '<a href="mailto:' + email + '" class="useremail">'
      emailEnd   = '</a>'
    else
      emailStart = ''
      emailEnd   = ''

    subject = "<span class=subject>#{subject or ''}</span>"

    userID =
      if !capcode and uniqueID
        " <span class='posteruid id_#{uniqueID}'>(ID: " +
          "<span class=hand title='Highlight posts by this ID'>#{uniqueID}</span>)</span> "
      else
        ''

    switch capcode
      when 'admin', 'admin_highlight'
        capcodeClass = " capcodeAdmin"
        capcodeStart = " <strong class='capcode hand id_admin'" +
          "title='Highlight posts by the Administrator'>## Admin</strong>"
        capcode      = " <img src='#{staticPath}/image/adminicon.gif' " +
          "alt='This user is the 4chan Administrator.' " +
          "title='This user is the 4chan Administrator.' class=identityIcon>"
      when 'mod'
        capcodeClass = " capcodeMod"
        capcodeStart = " <strong class='capcode hand id_mod' " +
          "title='Highlight posts by Moderators'>## Mod</strong>"
        capcode      = " <img src='#{staticPath}/image/modicon.gif' " +
          "alt='This user is a 4chan Moderator.' " +
          "title='This user is a 4chan Moderator.' class=identityIcon>"
      when 'developer'
        capcodeClass = " capcodeDeveloper"
        capcodeStart = " <strong class='capcode hand id_developer' " +
          "title='Highlight posts by Developers'>## Developer</strong>"
        capcode      = " <img src='#{staticPath}/image/developericon.gif' " +
          "alt='This user is a 4chan Developer.' " +
          "title='This user is a 4chan Developer.' class=identityIcon>"
      else
        capcodeClass = ''
        capcodeStart = ''
        capcode      = ''

    flag =
      if flagCode
       " <img src='#{staticPath}/image/country/#{if board is 'pol' then 'troll/' else ''}" +
        flagCode.toLowerCase() + ".gif' alt=#{flagCode} title='#{flagName}' class=countryFlag>"
      else
        ''

    if file?.isDeleted
      fileHTML =
        if isOP
          "<div class=file id=f#{postID}><div class=fileInfo></div><span class=fileThumb>" +
              "<img src='#{staticPath}/image/filedeleted.gif' alt='File deleted.' class='fileDeleted retina'>" +
          "</span></div>"
        else
          "<div id=f#{postID} class=file><span class=fileThumb>" +
            "<img src='#{staticPath}/image/filedeleted-res.gif' alt='File deleted.' class='fileDeletedRes retina'>" +
          "</span></div>"
    else if file
      ext = file.name[-3..]
      if !file.twidth and !file.theight and ext is 'gif' # wtf ?
        file.twidth  = file.width
        file.theight = file.height

      fileSize = $.bytesToString file.size

      fileThumb = file.turl
      if file.isSpoiler
        fileSize = "Spoiler Image, #{fileSize}"
        unless isArchived
          fileThumb = '//static.4chan.org/image/spoiler'
          if spoilerRange = Build.spoilerRange[board]
            # Randomize the spoiler image.
            fileThumb += "-#{board}" + Math.floor 1 + spoilerRange * Math.random()
          fileThumb += '.png'
          file.twidth = file.theight = 100

      imgSrc = "<a class='fileThumb#{if file.isSpoiler then ' imgspoiler' else ''}' href='#{file.url}' target=_blank>" +
        "<img src='#{fileThumb}' alt='#{fileSize}' data-md5=#{file.MD5} style='width:#{file.twidth}px;height:#{file.theight}px'></a>"

      # Ha Ha filenames.
      # html -> text, translate WebKit's %22s into "s
      a = $.el 'a', innerHTML: file.name
      filename = a.textContent.replace /%22/g, '"'

      # shorten filename, get html
      a.textContent = Build.shortFilename filename
      shortFilename = a.innerHTML

      # get html
      a.textContent = filename
      filename      = a.innerHTML.replace /'/g, '&apos;'

      fileDims = if ext is 'pdf' then 'PDF' else "#{file.width}x#{file.height}"
      fileInfo = "<span class=fileText id=fT#{postID}#{if file.isSpoiler then " title='#{filename}'" else ''}>File: <a href='#{file.url}' target=_blank>#{file.timestamp}</a>" +
        "-(#{fileSize}, #{fileDims}#{
          if file.isSpoiler
            ''
          else
            ", <span title='#{filename}'>#{shortFilename}</span>"
        }" + ")</span>"

      fileHTML = "<div id=f#{postID} class=file><div class=fileInfo>#{fileInfo}</div>#{imgSrc}</div>"
    else
      fileHTML = ''

    tripcode =
      if tripcode
        " <span class=postertrip>#{tripcode}</span>"
      else
        ''

    sticky =
      if isSticky
        ' <img src=//static.4chan.org/image/sticky.gif alt=Sticky title=Sticky style="height:16px;width:16px">'
      else
        ''
    closed =
      if isClosed
        ' <img src=//static.4chan.org/image/closed.gif alt=Closed title=Closed style="height:16px;width:16px">'
      else
        ''

    container = $.el 'div',
      id: "pc#{postID}"
      className: "postContainer #{if isOP then 'op' else 'reply'}Container"
      innerHTML: \
      (if isOP then '' else "<div class=sideArrows id=sa#{postID}>&gt;&gt;</div>") +
      "<div id=p#{postID} class='post #{if isOP then 'op' else 'reply'}#{
        if capcode is 'admin_highlight'
          ' highlightPost'
        else
          ''
        }'>" +

        (if isOP then fileHTML else '') +

        "<div class='postInfo desktop' id=pi#{postID}>" +
          "<input type=checkbox name=#{postID} value=delete> " +
          "#{subject} " +
          "<span class='nameBlock#{capcodeClass}'>" +
            emailStart +
              "<span class=name>#{name or ''}</span>" + tripcode +
            capcodeStart + emailEnd + capcode + userID + flag + sticky + closed +
          ' </span> ' +
          "<span class=dateTime data-utc=#{dateUTC}>#{date}</span> " +
          "<span class='postNum desktop'>" +
            "<a href=#{"/#{board}/res/#{threadID}#p#{postID}"} title='Highlight this post'>No.</a>" +
            "<a href='#{
              if g.REPLY and +g.THREAD_ID is threadID
                "javascript:quote(#{postID})"
              else
                "/#{board}/res/#{threadID}#q#{postID}"
              }' title='Quote this post'>#{postID}</a>" +
          '</span>' +
        '</div>' +

        (if isOP then '' else fileHTML) +

        "<blockquote class=postMessage id=m#{postID}>#{comment or ''}</blockquote> " +

      '</div>'

    for quote in $$ '.quotelink', container
      href = quote.getAttribute 'href'
      continue if href[0] is '/' # Cross-board quote, or board link
      quote.href = "/#{board}/res/#{href}" # Fix pathnames

    container
TitlePost =
  init: ->
    d.title = Get.title()

QuoteBacklink =
  init: ->
    format = Conf['backlink'].replace /%id/g, "' + id + '"
    @funk  = Function 'id', "return '#{format}'"
    Main.callbacks.push @node
  node: (post) ->
    return if post.isInlined
    quotes = {}
    for quote in post.quotes
      # Stop at 'Admin/Mod/Dev Replies:' on /q/
      break if quote.parentNode.parentNode.className is 'capcodeReplies'
      # Don't process >>>/b/.
      if quote.hostname is 'boards.4chan.org' and !/catalog$/.test(quote.pathname) and qid = quote.hash?[2..]
        # Duplicate quotes get overwritten.
        quotes[qid] = true
    a = $.el 'a',
      href: "/#{g.BOARD}/res/#{post.threadID}#p#{post.ID}"
      className: if post.el.hidden then 'filtered backlink' else 'backlink'
      textContent: QuoteBacklink.funk post.ID
    for qid of quotes
      # Don't backlink the OP.
      continue if !(el = $.id "pi#{qid}") or !Conf['OP Backlinks'] and /\bop\b/.test el.parentNode.className
      link = a.cloneNode true
      if Conf['Quote Preview']
        $.on link, 'mouseover', QuotePreview.mouseover
      if Conf['Quote Inline']
        $.on link, 'click', QuoteInline.toggle
      unless container = $.id "blc#{qid}"
        $.addClass el.parentNode, 'quoted'
        container = $.el 'span',
          className: 'container'
          id: "blc#{qid}"
        $.add el, container
      $.add container, [$.tn(' '), link]
      unless Conf["Backlinks Position"] is "default" or /\bop\b/.test el.parentNode.className
        el.parentNode.style.paddingBottom = "#{container.offsetHeight}px"
    return

QuoteInline =
  init: ->
    Main.callbacks.push @node

  node: (post) ->
    for quote in post.quotes
      continue unless quote.hash and quote.hostname is 'boards.4chan.org' and !/catalog$/.test(quote.pathname) or /\bdeadlink\b/.test quote.className
      $.on quote, 'click', QuoteInline.toggle
    for quote in post.backlinks
      $.on quote, 'click', QuoteInline.toggle
    return

  toggle: (e) ->
    return if e.shiftKey or e.altKey or e.ctrlKey or e.metaKey or e.button isnt 0
    e.preventDefault()
    id = @dataset.id or @hash[2..]
    if /\binlined\b/.test @className
      QuoteInline.rm @, id
    else
      return if $.x "ancestor::div[contains(@id,'p#{id}')]", @
      QuoteInline.add @, id
    $.toggleClass @, 'inlined'

  add: (q, id) ->
    if q.host is 'boards.4chan.org'
      path     = q.pathname.split '/'
      board    = path[1]
      threadID = path[3]
      postID   = id
    else
      board    = q.dataset.board
      threadID = 0
      postID   = q.dataset.id

    el = if board is g.BOARD then $.id "p#{postID}" else false
    inline = $.el 'div',
      id: "i#{postID}"
      className: if el then 'inline' else 'inline crosspost'

    root =
      if isBacklink = /\bbacklink\b/.test q.className
        q.parentNode
      else
        $.x 'ancestor-or-self::*[parent::blockquote][1]', q
    $.after root, inline
    Get.post board, threadID, postID, inline

    return unless el

    # Will only unhide if there's no inlined backlinks of it anymore.
    if isBacklink and Conf['Forward Hiding']
      $.addClass el.parentNode, 'forwarded'
      ++el.dataset.forwarded or el.dataset.forwarded = 1

    # Decrease the unread count if this post is in the array of unread reply.
    if (i = Unread.replies.indexOf el) isnt -1
      Unread.replies.splice i, 1
      Unread.update true

    if Conf['Color user IDs'] and ['b', 'q', 'soc'].contains board
      setTimeout -> $.rmClass $('.reply.highlight', inline), 'highlight'

  rm: (q, id) ->
    # select the corresponding inlined quote or loading quote
    div = $.x "following::div[@id='i#{id}']", q
    $.rm div
    return unless Conf['Forward Hiding']
    for inlined in $$ '.backlink.inlined', div
      div = $.id inlined.hash[1..]
      $.rmClass div.parentNode, 'forwarded' unless --div.dataset.forwarded
    if /\bbacklink\b/.test q.className
      div = $.id "p#{id}"
      $.rmClass div.parentNode, 'forwarded' unless --div.dataset.forwarded

QuotePreview =
  init: ->
    Main.callbacks.push @node

    $.ready -> $.add d.body, QuotePreview.el = $.el 'div',
      id: 'qp'
      className: 'reply dialog'

  node: (post) ->
    for quote in post.quotes
      continue unless quote.hostname is 'boards.4chan.org' and quote.hash and !/catalog$/.test(quote.pathname) or /\bdeadlink\b/.test quote.className
      $.on quote, 'mouseover', QuotePreview.mouseover
    for quote in post.backlinks
      $.on quote, 'mouseover', QuotePreview.mouseover
    return

  mouseover: (e) ->
    return if /\binlined\b/.test @className

    qp = QuotePreview.el

    # Make sure to remove the previous qp
    # in case it got stuck.
    if UI.el
      if qp is UI.el
        delete UI.el

      # Don't stop other elements from dragging
      else
        return

    if @host is 'boards.4chan.org'
      path     = @pathname.split '/'
      board    = path[1]
      threadID = path[3]
      postID   = @hash[2..]
    else
      board    = @dataset.board
      threadID = 0
      postID   = @dataset.id

    UI.el = qp
    UI.hover e

    Get.post board, threadID, postID, qp, ->
      _conf = Conf
      bq = $ 'blockquote', qp
      Main.prettify bq
      post =
        el: qp
        blockquote: bq
        isArchived: qp.className.contains 'archivedPost'
      if img = $ 'img[data-md5]', qp
        post.fileInfo = img.parentNode.previousElementSibling
        post.img      = img
      if _conf['Reveal Spoilers']
        RevealSpoilers.node post
      if _conf['Time Formatting']
        Time.node           post
      if _conf['File Info Formatting']
        FileInfo.node       post
      if _conf['Linkify']
        Linkify.node        post
      if _conf['Resurrect Quotes']
        Quotify.node        post
      if _conf['Anonymize']
        Anonymize.node      post
      if _conf['Replace GIF'] or _conf['Replace PNG'] or _conf['Replace JPG']
        ImageReplace.node   post
      if _conf['Color user IDs'] and ['b', 'q', 'soc'].contains board
        IDColor.node        post
      if _conf['RemoveSpoilers']
        RemoveSpoilers.node post

    $.on @, 'mousemove',      UI.hover
    $.on @, 'mouseout click', QuotePreview.mouseout

    _conf = Conf

    if _conf['Fappe Tyme']
      $.rmClass qp.firstElementChild, 'noFile'

    if el = $.id "p#{postID}"
      _conf = Conf
      if _conf['Quote Highlighting']
        if /\bop\b/.test el.className
          $.addClass el.parentNode, 'qphl'
        else
          $.addClass el, 'qphl'

      quoterID = $.x('ancestor::*[@id][1]', @).id.match(/\d+$/)[0]
      for quote in $$ '.quotelink, .backlink', qp
        if quote.hash[2..] is quoterID
          $.addClass quote, 'forwardlink'

  mouseout: (e) ->
    delete UI.el
    $.rm QuotePreview.el.firstChild
    if (hash = @hash) and el = $.id hash[1..]
      $.rmClass el.parentNode, 'qphl' # op
      $.rmClass el,            'qphl' # reply

    $.off @, 'mousemove',      UI.hover
    $.off @, 'mouseout click', QuotePreview.mouseout

QuoteOP =
  init: ->
    Main.callbacks.push @node
  node: (post) ->
    return if post.isInlined and not post.isCrosspost
    for quote in post.quotes
      if quote.hash[2..] is post.threadID
        # \u00A0 is nbsp
        $.add quote, $.tn '\u00A0(OP)'
    return

QuoteCT =
  init: ->
    Main.callbacks.push @node
  node: (post) ->
    return if post.isInlined and not post.isCrosspost
    for quote in post.quotes
      unless quote.hash and quote.hostname is 'boards.4chan.org' and !/catalog$/.test quote.pathname
        # Make sure this isn't a link to the board we're on.
        continue
      path = quote.pathname.split '/'
      # If quote leads to a different thread id and is located on the same board.
      if path[1] is g.BOARD and path[3] isnt post.threadID
        # \u00A0 is nbsp
        $.add quote, $.tn '\u00A0(Cross-thread)'
    return

IDColor =
  init: ->
    return unless ['b', 'q', 'soc'].contains g.BOARD
    Main.callbacks.push @node

  node: (post) ->
    return unless uid = $ '.postInfo .hand', post.el
    str = uid.textContent
    if uid.nodeName is 'SPAN'
      uid.style.cssText = IDColor.apply.call str

    unless IDColor.highlight[str]
      IDColor.highlight[str] = []

    if str is $.get "highlightedID/#{g.BOARD}/"
      IDColor.highlight.current.push post
      $.addClass post.el, 'highlight'

    IDColor.highlight[str].push post
    $.on uid, 'click', -> IDColor.idClick str

  ids: {}

  compute: (str) ->
    hash = @hash str

    rgb = [
      (hash >> 24) & 0xFF
      (hash >> 16) & 0xFF
      (hash >> 8)  & 0xFF
    ]
    rgb[3] = ((rgb[0] * 0.299) + (rgb[1] * 0.587) + (rgb[2] * 0.114)) > 125

    @ids[str] = rgb
    rgb

  apply: ->
    rgb = IDColor.ids[@] or IDColor.compute @
    "background-color: rgb(#{rgb[0]},#{rgb[1]},#{rgb[2]}); color: " + if rgb[3] then "black;" else "white;"

  hash: (str) ->
    msg = 0
    i = 0
    j = str.length
    while i < j
      msg = ((msg << 5) - msg) + str.charCodeAt i
      ++i
    msg
  highlight:
    current: []

  idClick: (str) ->
    for post in @highlight.current
      $.rmClass post.el, 'highlight'
    last = $.get value = "highlightedID/#{g.BOARD}/", false
    if str is last
      @highlight.current = []
      return $.delete value

    for post in @highlight[str]
      continue if post.isInlined
      $.addClass post.el, 'highlight'
      @highlight.current.push post
    $.set value, str

Quotify =
  init: ->
    Main.callbacks.push @node
  node: (post) ->
    return if post.isInlined and not post.isCrosspost
    for deadlink in $$ '.deadlink', post.blockquote
      quote = deadlink.textContent
      a = $.el 'a',
        # \u00A0 is nbsp
        textContent: "#{quote}\u00A0(Dead)"

      continue unless id = quote.match(/\d+$/)
      id = id[0]

      if m = quote.match /^>>>\/([a-z\d]+)/
        board = m[1]
      else if postBoard
        board = postBoard
      else
        # Get the post's board, whether it's inlined or not.
        board = postBoard = $('a[title="Highlight this post"]', post.el).pathname.split('/')[1]

      if board is g.BOARD and $.id "p#{id}"
        a.href = "#p#{id}"
        a.className = 'quotelink'
      else
        a.href =
          Redirect.to
            board: board
            threadID: 0
            postID: id
        a.className = 'deadlink'
        a.target = '_blank'
        if Redirect.post board, id
          $.addClass a, 'quotelink'
          # XXX WTF Scriptish/Greasemonkey?
          # Setting dataset attributes that way doesn't affect the HTML,
          # but are, I suspect, kept as object key/value pairs and GC'd later.
          # a.dataset.board = board
          # a.dataset.id = id
          a.setAttribute 'data-board', board
          a.setAttribute 'data-id', id
      $.replace deadlink, a
    return

Linkify =
  init: ->
    Main.callbacks.push @node

  regString: ///(
    \b(
      [a-z]+:// # http://, ftp://
      |
      [-a-z0-9]+\.[-a-z0-9]+\.[-a-z0-9]+ # www.test-9.com
      |
      [-a-z0-9]+\.[a-z]{3} # this-is-my-web-sight.net.
      |
      [a-z]+:[a-z0-9] # mailto:, magnet:
      |
      [a-z0-9._%+-:]+@[a-z0-9.-]+\.[a-z0-9] # E-mails, also possibly anonymous:password@192.168.2.1
    )
    [^\s,]+ # Terminate at Whitespace
  )///gi

  cypher: $.el 'div'

  node: (post) ->
    if post.isInlined and not post.isCrosspost
      if Conf['Embedding']
        for embed in $$('.embed', post.blockquote)
          $.on embed, 'click', Linkify.toggle
      return

    snapshot = d.evaluate './/text()', post.blockquote, null, 6, null

    # By using an out-of-document element to hold text I
    # can use the browser's methods and properties for
    # character escaping, instead of depending on loose code
    cypher   = Linkify.cypher
    i        = -1
    len      = snapshot.snapshotLength

    while ++i < len
      nodes = []
      node  = snapshot.snapshotItem i
      data  = node.data

      # Test for valid links
      continue unless node.parentElement and Linkify.regString.test data

      # Regex.test stores the index of its last match.
      # Because I am matching different nodes, this causes issues,
      # like the next checked line failing to test
      # (which also resets ...lastIndex)
      Linkify.regString.lastIndex = 0

      cypherText = []

      if next = node.nextSibling
        # This is one of the few examples in JS where what you
        # put into a variable is different than what comes out
        cypher.innerHTML = node.textContent
        cypherText[0]    = cypher.innerHTML

        # i herd u leik wbr
        while (next.nodeName.toLowerCase() is 'wbr' or next.nodeName.toLowerCase() is 's') and (lookahead = next.nextSibling) and ((name = lookahead.nodeName) is "#text" or name.toLowerCase() is 'br')
          cypher.innerHTML = lookahead.textContent

          cypherText.push if spoiler = next.innerHTML then "<s>#{spoiler.replace /</g, ' <'}</s>" else '<wbr>'
          cypherText.push cypher.innerHTML

          $.rm next
          next = lookahead.nextSibling
          $.rm lookahead if lookahead.nodeName is "#text"

          unless next
            break

      if cypherText.length
        data = cypherText.join ''

      # Re-check for links due to string merging.
      links = data.match Linkify.regString

      for link in links
        index = data.indexOf link

        # Potential text before this valid link.
        # Convert <wbr> and spoilers into elements
        if text = data[...index]
          # press button get bacon
          cypher.innerHTML = text
          for child in cypher.childNodes
            nodes.push child

        cypher.innerHTML = (if link.indexOf(':') < 0 then (if link.indexOf('@') > 0 then 'mailto:' + link else 'http://' + link) else link).replace /<(wbr|s|\/s)>/g, ''

        # The bloodied text walked away, mangled
        # Attributes dropping out its opened gut
        # For the RegEx Blade vibrated violently
        # Ripping and tearing as it classified a
        # Poor piece of prose out of its element
        # Injured anchor arose an example of art
        a = $.el 'a',
          innerHTML: link
          className: 'linkify'
          rel:       'nofollow noreferrer'
          target:    'blank'
          href:      cypher.textContent

        # To die and rot inside burning embedder
        nodes = nodes.concat Linkify.embedder a

        # The survivor shot down with no remorse
        data = data[index + link.length..]

      if data
        # Potential text after the last valid link.
        # & Convert <wbr> into elements
        cypher.innerHTML = data

        # Convert <wbr> into elements
        for child in cypher.childNodes
          nodes.push child

      # They were replaced with constructs.
      $.replace node, nodes

  toggle: ->
    # We setup the link to be replaced by the embedded video
    embed = @previousElementSibling

    # Unembed.
    if @className.contains "embedded"
      # Recreate the original link.
      el = $.el 'a'
        rel:         'nofollow noreferrer'
        target:      'blank'
        className:   'linkify'
        href:        url = @getAttribute("data-originalURL")
        textContent: @getAttribute("data-title") or url

      @textContent = '(embed)'

    # Embed
    else
      # We create an element to embed
      el = (type = Linkify.types[@getAttribute("data-service")]).el.call @

      # Set style values.
      el.style.cssText = if style = type.style
        style
      else
        "border: 0; width: #{$.get 'embedWidth', Config['embedWidth']}px; height: #{$.get 'embedHeight', Config['embedHeight']}px"

      @textContent = '(unembed)'

    $.replace embed, el
    $.toggleClass @, 'embedded'

  types:
    YouTube:
      regExp:  /.*(?:youtu.be\/|youtube.*v=|youtube.*\/embed\/|youtube.*\/v\/|youtube.*videos\/)([^#\&\?]*).*/
      el: ->
        $.el 'iframe'
          src: "//www.youtube.com/embed/#{@name}"
      title:
        api:  -> "https://gdata.youtube.com/feeds/api/videos/#{@name}?alt=json&fields=title/text(),yt:noembed,app:control/yt:state/@reasonCode"
        text: -> JSON.parse(@responseText).entry.title.$t

    Vocaroo:
      regExp:  /.*(?:vocaroo.com\/)([^#\&\?]*).*/
      style: 'border: 0; width: 150px; height: 45px;'
      el: ->
        $.el 'object'
          innerHTML:  "<embed src='http://vocaroo.com/player.swf?playMediaID=#{@name.replace /^i\//, ''}&autoplay=0' width='150' height='45' pluginspage='http://get.adobe.com/flashplayer/' type='application/x-shockwave-flash'></embed>"

    Vimeo:
      regExp:  /.*(?:vimeo.com\/)([^#\&\?]*).*/
      el: ->
        $.el 'iframe'
          src: "//player.vimeo.com/video/#{@name}"
      title:
        api:  -> "https://vimeo.com/api/oembed.json?url=http://vimeo.com/#{@name}"
        text: -> JSON.parse(@responseText).title

    LiveLeak:
      regExp:  /.*(?:liveleak.com\/view.+i=)([0-9a-z_]+)/
      el: ->
        $.el 'iframe'
          src: "http://www.liveleak.com/e/#{@name}?autostart=true"

    audio:
      regExp:  /(.*\.(mp3|ogg|wav))$/
      el: ->
        $.el 'audio'
          controls:    'controls'
          preload:     'auto'
          src:         @name

    SoundCloud:
      regExp:  /.*(?:soundcloud.com\/|snd.sc\/)([^#\&\?]*).*/
      el: ->
        div = $.el 'div'
          className: "soundcloud"
          name:      "soundcloud"
        $.ajax(
          "//soundcloud.com/oembed?show_artwork=false&&maxwidth=500px&show_comments=false&format=json&url=#{@getAttribute 'data-originalURL'}&color=#{Style.color.toHex Themes[Conf['theme']]['Background Color']}"
          div: div
          onloadend: ->
            @div.innerHTML = JSON.parse(@responseText).html
          false)
        div

  embedder: (a) ->
    return [a] unless Conf['Embedding']

    for key, type of Linkify.types
      continue unless match = a.href.match type.regExp

      embed = $.el 'a'
        name:         (a.name = match[1])
        className:    'embed'
        href:         'javascript:;'
        textContent:  '(embed)'

      embed.setAttribute 'data-service', key
      embed.setAttribute 'data-originalURL', a.href

      $.on embed, 'click', Linkify.toggle

      if Conf['Link Title'] and (service = type.title)
        titles = $.get 'CachedTitles', {}

        if title = titles[match[1]]
          a.textContent = title[0]
          embed.setAttribute 'data-title', title[0]
        else
          $.cache service.api.call(a), ->
            a.textContent = switch @status
              when 200, 304
                title = "[#{embed.getAttribute 'data-service'}] #{service.text.call @}"
                embed.setAttribute 'data-title', title
                titles[embed.name] = [title, Date.now()]
                $.set 'CachedTitles', titles
                title
              when 404
                "[#{key}] Not Found"
              when 403
                "[#{key}] Forbidden or Private"
              else
                "[#{key}] #{@status}'d"

        return [a, $.tn(' '), embed]
    return [a]

DeleteLink =
  init: ->
    div = $.el 'div',
      className: 'delete_link'
      textContent: 'Delete'
    aPost = $.el 'a',
      className: 'delete_post'
      href: 'javascript:;'
    aImage = $.el 'a',
      className: 'delete_image'
      href: 'javascript:;'

    children = []

    children.push
      el: aPost
      open: ->
        aPost.textContent = 'Post'
        $.on aPost, 'click', DeleteLink.delete
        true

    children.push
      el: aImage
      open: (post) ->
        return false unless post.img
        aImage.textContent = 'Image'
        $.on aImage, 'click', DeleteLink.delete
        true

    Menu.addEntry
      el: div
      open: (post) ->
        if post.isArchived
          return false
        node = div.firstChild
        if seconds = DeleteLink.cooldown[post.ID]
          node.textContent = "Delete (#{seconds})"
          DeleteLink.cooldown.el = node
        else
          node.textContent = 'Delete'
          delete DeleteLink.cooldown.el
        true
      children: children

    $.on d, 'QRPostSuccessful', @cooldown.start

  delete: ->
    menu = $.id 'menu'
    {id} = menu.dataset
    return if DeleteLink.cooldown[id]

    $.off @, 'click', DeleteLink.delete
    @textContent = 'Deleting...'

    pwd =
      if m = d.cookie.match /4chan_pass=([^;]+)/
        decodeURIComponent m[1]
      else
        $.id('delPassword').value

    board = $('a[title="Highlight this post"]',
      $.id menu.dataset.rootid).pathname.split('/')[1]
    self = @

    form =
      mode: 'usrdel'
      onlyimgdel: /\bdelete_image\b/.test @className
      pwd: pwd
    form[id] = 'delete'

    $.ajax $.id('delform').action.replace("/#{g.BOARD}/", "/#{board}/"), {
        onload:  -> DeleteLink.load  self, @response
        onerror: -> DeleteLink.error self
      }, {
        form: $.formData form
      }
  load: (self, html) ->
    doc = d.implementation.createHTMLDocument ''
    doc.documentElement.innerHTML = html
    if doc.title is '4chan - Banned' # Ban/warn check
      s = 'Banned!'
    else if msg = doc.getElementById 'errmsg' # error!
      s = msg.textContent
      $.on self, 'click', DeleteLink.delete
    else
      s = 'Deleted'
    self.textContent = s
  error: (self) ->
    self.textContent = 'Connection error, please retry.'
    $.on self, 'click', DeleteLink.delete

  cooldown:
    start: (e) ->
      seconds =
        if g.BOARD is 'q'
          600
        else
          30
      DeleteLink.cooldown.count e.detail.postID, seconds, seconds
    count: (postID, seconds, length) ->
      return unless 0 <= seconds <= length
      setTimeout DeleteLink.cooldown.count, 1000, postID, seconds-1, length
      {el} = DeleteLink.cooldown
      if seconds is 0
        el?.textContent = 'Delete'
        delete DeleteLink.cooldown[postID]
        delete DeleteLink.cooldown.el
        return
      el?.textContent = "Delete (#{seconds})"
      DeleteLink.cooldown[postID] = seconds

ReportLink =
  init: ->
    a = $.el 'a',
      className: 'report_link'
      href: 'javascript:;'
      textContent: 'Report this post'
    $.on a, 'click', @report
    Menu.addEntry
      el: a
      open: (post) ->
        post.isArchived is false
  report: ->
    a   = $ 'a[title="Highlight this post"]', $.id @parentNode.dataset.rootid
    url = "//sys.4chan.org/#{a.pathname.split('/')[1]}/imgboard.php?mode=report&no=#{@parentNode.dataset.id}"
    id  = Date.now()
    set = "toolbar=0,scrollbars=0,location=0,status=1,menubar=0,resizable=1,width=685,height=200"
    window.open url, id, set

DownloadLink =
  init: ->
    # Test for download feature support.
    return unless $.el('a').download?
    a = $.el 'a',
      className: 'download_link'
      textContent: 'Download file'
    Menu.addEntry
      el: a
      open: (post) ->
        unless post.img
          return false
        a.href     = post.img.parentNode.href
        fileText   = post.fileInfo.firstElementChild
        a.download =
          if Conf['File Info Formatting']
            fileText.dataset.filename
          else
            $('span', fileText).title
        true

ArchiveLink =
  init: ->
    div = $.el 'div',
      textContent: 'Archive'

    entry =
      el: div
      open: (post) ->
        path = $('a[title="Highlight this post"]', post.el).pathname.split '/'
        if (Redirect.to {board: path[1], threadID: path[3], postID: post.ID}) is "//boards.4chan.org/#{path[1]}/"
          return false
        post.info = [path[1], path[3]]
        true
      children: []

    for key, type of {
      Post:        'apost'
      Name:        'name'
      Tripcode:    'tripcode'
      'E-mail':    'email'
      Subject:     'subject'
      Filename:    'filename'
      'Image MD5': 'md5'
    }
      # Add a sub entry for each type.
      entry.children.push @createSubEntry key, type

    Menu.addEntry entry

  createSubEntry: (text, type) ->

    el = $.el 'a',
      textContent: text
      target: '_blank'

    open = (post) ->
      if type is 'apost'
        el.href =
          Redirect.to
            board:    post.info[0]
            threadID: post.info[1]
            postID:   post.ID
        return true
      value = Filter[type] post
      # We want to parse the exact same stuff as Filter does already.
      return false unless value
      el.href =
        Redirect.to
          board:    post.info[0]
          type:     type
          value:    value
          isSearch: true

    return el: el, open: open

ThreadHideLink =
  init: ->
    # If ThreadHiding hasn't been initialized, we have to fake it.
    unless Conf['Thread Hiding']
      $.ready @iterate

    a = $.el 'a',
      className: 'thread_hide_link'
      href: 'javascript:;'
      textContent: 'Hide / Restore Thread'
    $.on a, 'click', ->
      menu   = $.id 'menu'
      thread = $.id "t#{menu.dataset.id}"
      ThreadHiding.toggle thread
    Menu.addEntry
      el: a
      open: (post) ->
        if post.el.classList.contains 'op' then true else false

  iterate: ->
    ThreadHiding.hiddenThreads = $.get "hiddenThreads/#{g.BOARD}/", {}
    for thread in $$ '.thread'
      if thread.id[1..] of ThreadHiding.hiddenThreads
        ThreadHiding.hide thread
    return

ReplyHideLink =
  init: ->
    # Fake reply hiding functionality if it is disabled.
    unless Conf['Reply Hiding']
      Main.callbacks.push @node

    a = $.el 'a',
      className: 'reply_hide_link'
      href: 'javascript:;'
      textContent: 'Hide / Restore Post'

    $.on a, 'click', ->
      menu   = $.id 'menu'
      id     = menu.dataset.id
      root   = $.id "pc#{id}"
      button = root.firstChild
      ReplyHiding.toggle button, root, id

    Menu.addEntry
      el: a
      open: (post) ->
        if post.isInlined or post.el.classList.contains 'op' then false else true

  node: (post) ->
    return if post.isInlined or post.ID is post.threadID

    if post.ID of g.hiddenReplies
      ReplyHiding.hide post.root

EmbedLink =
  init: ->
    a = $.el 'a'
      className: 'embed_link'
      textContent: 'Embed all in post'

    $.on a, 'click', EmbedLink.toggle

    Menu.addEntry
      el: a
      open: (post) ->
        if $ '.embed', (quote = post.blockquote)
          if $ '.embedded', quote
            @el.textContent = 'Unembed all in post'
            EmbedLink[post.id] = true
          $.on @el, 'click', @toggle
          return true
        false

  toggle: ->
    menu   = $.id 'menu'
    id     = menu.dataset.id
    root   = $.id "m#{id}"

    for embed in $$ '.embed', root
      if (!EmbedLink[id] and embed.className.contains 'embedded') or (EmbedLink[id] and !embed.className.contains 'embedded')
        continue
      embed.click()
    EmbedLink[id] = !EmbedLink[id]

ThreadStats =
  init: ->
    ThreadStats.postcount = $.el 'span'
      id:          'postcount'
      textContent: '0'
    ThreadStats.imagecount = $.el 'span'
      id:          'imagecount'
      textContent: '0'
    if Conf['Thread Updater'] and move = Updater.count.parentElement
      container = $.el 'span'
      $.add container, $.tn('[')
      $.add container, ThreadStats.postcount
      $.add container, $.tn(' / ')
      $.add container, ThreadStats.imagecount
      $.add container, $.tn('] ')
      $.prepend move, container
    else
      dialog = UI.dialog 'stats', 'bottom: 0; left: 0;', '<div class=move></div>'
      dialog.className = 'dialog'
      $.add $(".move", dialog), ThreadStats.postcount
      $.add $(".move", dialog), $.tn(" / ")
      $.add $(".move", dialog), ThreadStats.imagecount
      $.add d.body, dialog
    @posts = @images = 0
    @imgLimit =
      switch g.BOARD
        when 'a', 'b', 'v', 'co', 'mlp'
          251
        when 'vg'
          376
        else
          151
    Main.callbacks.push @node
  node: (post) ->
    return if post.isInlined
    ThreadStats.postcount.textContent = ++ThreadStats.posts
    return unless post.img

    ThreadStats.imagecount.textContent = ++ThreadStats.images
    if ThreadStats.images > ThreadStats.imgLimit
      $.addClass ThreadStats.imagecount, 'warning'

Unread =
  init: ->
    @title = d.title
    $.on d, 'QRPostSuccessful', @post
    @update()
    $.on window, 'scroll focus', Unread.scroll
    Main.callbacks.push @node

  replies: []
  foresee: []

  post: (e) ->
    Unread.foresee.push e.detail.postID

  node: (post) ->
    if (index = Unread.foresee.indexOf post.ID) isnt -1
      Unread.foresee.splice index, 1
      return
    {el} = post
    return if el.hidden or /\bop\b/.test(post.class) or post.isInlined
    count = Unread.replies.push el
    Unread.update count is 1

  scroll: ->
    height = d.documentElement.clientHeight
    for reply, i in Unread.replies
      {bottom} = reply.getBoundingClientRect()
      if bottom > height #post is not completely read
        break
    return if i is 0

    Unread.replies = Unread.replies[i..]
    Unread.update Unread.replies.length is 0

  setTitle: (count) ->
    if @scheduled
      clearTimeout @scheduled
      delete Unread.scheduled
      @setTitle count
      return
    @scheduled = setTimeout (->
      d.title = "(#{count}) #{Unread.title}"
    ), 5

  update: (updateFavicon) ->
    return unless g.REPLY

    count = @replies.length

    if Conf['Unread Count']
      @setTitle count

    unless Conf['Unread Favicon'] and updateFavicon
      return

    if $.engine is 'presto'
      $.rm Favicon.el

    Favicon.el.href =
      if g.dead
        if count
          Favicon.unreadDead
        else
          Favicon.dead
      else
        if count
          Favicon.unread
        else
          Favicon.default

    if g.dead
      $.addClass    Favicon.el, 'dead'
    else
      $.rmClass     Favicon.el, 'dead'
    if count
      $.addClass    Favicon.el, 'unread'
    else
      $.rmClass     Favicon.el, 'unread'

    # `favicon.href = href` doesn't work on Firefox
    # `favicon.href = href` isn't enough on Opera
    # Opera won't always update the favicon if the href didn't change
    unless $.engine is 'webkit'
      $.add d.head, Favicon.el

Favicon =
  init: ->
    return if @el # Prevent race condition with options first run
    @el = $ 'link[rel="shortcut icon"]', d.head
    @el.type = 'image/x-icon'
    {href} = @el
    @SFW = /ws.ico$/.test href
    @default = href
    @switch()

  switch: ->
    @unreadDead = @unreadSFW = @unreadNSFW = Icons.header.png
    switch Conf['favicon']
      when 'ferongr'
        @unreadDead += 'BAAAAAQBAMAAADt3eJSAAAAD1BMVEWrVlbpCwJzBQD/jIzlCgLerRyUAAAAAXRSTlMAQObYZgAAAFhJREFUeF5Fi8ENw0AMw6gNZHcCXbJAkw2C7D9Tz68KJKAP+a8MKtAK9DJ9X9ZxB+WT/rbpt9L1Bq3lEapGgBqY3hvYfTagY6rLKHPa6DzTz2PothJAApsfXPUIxXEAtJ4AAAAASUVORK5CYII='
        @unreadNSFW += 'BAAAAAQCAMAAAAoLQ9TAAAAFVBMVEWJq3ho/gooegBJ3ABU/QBW/wHV/8Hz/s/JAAAAAnRSTlMAscr1TiIAAABVSURBVBjTZY5LDgAxCEKNovc/8mgozq9d+CQRMPs/AC+Auz8BXlUfyGzoPZN7xNDoEVR0u2Zy3ziTsEV0oj5eTCn1KaVQGTpCHiH64wzegKZYV8M9Lia0Aj8l3NBcAAAAAElFTkSuQmCC'
        @unreadSFW  += 'BAAAAAQCAMAAAAoLQ9TAAAAFVBMVEUAS1QAnbAAsseF5vMA2fMA1/EAb37J/JegAAAAA3RSTlMAmPz35Xr7AAAAUUlEQVQY02WOCQ4AIQgDSUr5/5Pl9NjVhE6bYBX5H5IP0MxuoAH4gKqDe9XyZFDkPlirt+bjjyae2X2cWR7VgvkPpqWSoA60g7wtMsmWTIRHFpbuAyerdnAvAAAAAElFTkSuQmCC'
      when 'xat-'
        @unreadDead += 'BAAAAAQBAMAAADt3eJSAAAAG1BMVEXzZmTzZGLzZGLzZGIAAAD/AAD/lJX4bWz/0tMaHcyBAAAABHRSTlMAm8l+71ABtwAAAFpJREFUeF5ty9EJgDAQA9B8dIGKC1gcoQNUm+ICvRWKAwjdwLklCAXBfD2SO/yE2ftIwFkNoVgCih2XVTWCGrI1EsDUz7svH2gSoo4zxruwry/KNlfBOSAljDwk8xZR3HxWZAAAAABJRU5ErkJggg=='
        @unreadNSFW += 'BAAAAAQBAMAAADt3eJSAAAAIVBMVEVirGJdqF9dqF9dqF9dqF9082JmzDOq/5oAAACR/33Z/9JztnAYAAAABXRSTlMAyZ2Ses9C/CQAAABjSURBVHhebcsxDkBAFATQKbddGq1otJxij8AFJnsFqiVr8x1AuIFr8iMRhaleZv7HTyS2lRPA0FubGIDEpaPXhutBbUT2QQRA2Y/nln3R6JQDcHoc8b4rpuJBmmuvMAYIAW8utWkfv3LWVYEAAAAASUVORK5CYII='
        @unreadSFW  += 'BAAAAAQBAMAAADt3eJSAAAAHlBMVEUAAABde6Zde6Zde6Zde6aQz/8umMNquPcAAADQ6/+nHRY3AAAABXRSTlMAyZ16kvc074oAAABfSURBVHhebcuxCYAwFIThv0yrWNgKFo6QVnewcIFHNohlNBDfAu4rDyFYeNXHHcdPNC+jV3ASmqZIgiLXLsEagzWq66oKDHG7Y/vFbFMHeHtl6t1w9C/KOQWDc5ASNQ9glx6N+XFPbgAAAABJRU5ErkJggg=='
      when 'Mayhem'
        @unreadDead += 'BAAAAAQBAMAAADt3eJSAAAAHlBMVEUAAAAAAAAAAAAAAAAAAAATExMBAQEAAAD/AAD///+gujywAAAACHRSTlMPJRcbLzEcM37+zgIAAAB9SURBVHheRcu9DoJAEATgcX0B+Wns7uAFRGgoCVhQ0phca8K77JXEI+6+rUujU32ZzOAXanLAFw5e91cdNEfPcVmF3+iEt8BxtOaANV51WdU2VE5FMw0O1B0YDaUOD30aZk6Bd4eT8Mfulz/OIinEeANd5yxLmwPqtqraO75dUSZT40SwmAAAAABJRU5ErkJggg=='
        @unreadNSFW += 'BAAAAAQBAMAAADt3eJSAAAAHlBMVEUAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD///9mzDPTSEsdAAAACHRSTlMaDCUeLg4zKeknoAsAAACHSURBVHheJcqxCsIwEMbxLw2CY27oLiSCYwioeyjS0Sp9Ah26d+koUtrkDXJv6xXhhj+/70B9R1T3BBN8V2urUKXV6ykdsOcSXeYPLpnXictLZAuRKqXokvzc3duGW9zBXBsbmlHBuG2KEi3PcgrPzMvA5YzHP44ieW6LiDkNNixfBYIHNOgHHmcn+8KfmKQAAAAASUVORK5CYII='
        @unreadSFW  += 'BAAAAAQBAMAAADt3eJSAAAAG1BMVEUAAAAAAAABAwMAAAAAAAAAAAAAAAAumMP///+/4sWwAAAAB3RSTlMVJxQdMSkcONaevAAAAIJJREFUeF4lirEKgzAURa9PcBai4PjI0NlA6y61kFXawVHq4h+8rEI0+ewmdLqHcw80SGtOw2Yg3hShiGdfLrHGLm5ug1y4Bzk6cc9kMiRTxDi3MTVVMykzjSv48VLm8yZwk6+RcFvEWzm/KEMG16P4Q51M8NYlw51Vxh8EXQ3AtuofzNIkEO8Bb0kAAAAASUVORK5CYII='
      when 'Original'
        @unreadDead += 'BAAAAAQCAMAAAAoLQ9TAAAAD1BMVEWYmJiYmJj///8AAAD/AACKRYF4AAAAAnRSTlMAvLREMp8AAABFSURBVBjTbY7BDgAgCEIZ+P/f3MGgXHkR3wYCvENyCEq6BVVVPzFvg03sTZjT8w4GKWKL+8ih7jPffoEaKB52KJMKnrUA5kwBxesBDg0AAAAASUVORK5CYII='
        @unreadNSFW += 'BAAAAAQCAMAAAAoLQ9TAAAADFBMVEWYmJj///9mzDMAAAADduU3AAAAAXRSTlMAQObYZgAAAERJREFUGNNtjkESACAIAkH+/+cOBuWUF3FnQIB3SA5BSbegquon5m2wib0Jc3rewSBFbHEfOdR95tsvUAPFww5lUsGzFpsgATH7KrmBAAAAAElFTkSuQmCC'
        @unreadSFW  += 'BAAAAAQCAMAAAAoLQ9TAAAADFBMVEWYmJj///8umMMAAACriBKaAAAAAXRSTlMAQObYZgAAAERJREFUGNNtjkESACAIAkH+/+cOBuWUF3FnQIB3SA5BSbegquon5m2wib0Jc3rewSBFbHEfOdR95tsvUAPFww5lUsGzFpsgATH7KrmBAAAAAElFTkSuQmCC'
    @unread = if @SFW then @unreadSFW else @unreadNSFW

  empty: 'data:image/gif;base64,R0lGODlhEAAQAJEAAAAAAP///9vb2////yH5BAEAAAMALAAAAAAQABAAAAIvnI+pq+D9DBAUoFkPFnbs7lFZKIJOJJ3MyraoB14jFpOcVMpzrnF3OKlZYsMWowAAOw=='
  dead:  'data:image/gif;base64,R0lGODlhEAAQAKECAAAAAP8AAP///////yH5BAEKAAIALAAAAAAQABAAAAIvlI+pq+D9DAgUoFkPDlbs7lFZKIJOJJ3MyraoB14jFpOcVMpzrnF3OKlZYsMWowAAOw=='

Redirect =
  image: (board, filename) ->
    # Do not use g.BOARD, the image url can originate from a cross-quote.
    switch board
      when 'a', 'jp', 'm', 'q', 'sp', 'tg', 'vg', 'wsg'
        "//archive.foolz.us/#{board}/full_image/#{filename}"
      when 'cgl', 'g', 'mu', 'w'
        "//rbt.asia/#{board}/full_image/#{filename}"
      when 'an', 'k', 'toy', 'x'
        "http://archive.heinessen.com/#{board}/full_image/#{filename}"
      when 'ck', 'lit'
        "//fuuka.warosu.org/#{board}/full_image/#{filename}"
      when 'u'
        "//nsfw.foolz.us/#{board}/full_image/#{filename}"
      when 'e'
        "//www.xn--clich-fsa.net/4chan/cgi-board.pl/#{board}/img/#{filename}"
      when 'c'
        "//archive.nyafuu.org/#{board}/full_image/#{filename}"

  post: (board, postID) ->
    if Redirect.post[board] is undefined
      for name, archive of @archiver
        if archive.type is 'foolfuuka' and archive.boards.contains board
          Redirect.post[board] = archive.base
          break
      Redirect.post[board] or= null

    if Redirect.post[board]
      return "#{Redirect.post[board]}/_/api/chan/post/?board=#{board}&num=#{postID}"
    null

  archiver:
    'Foolz':
      base:    '//archive.foolz.us'
      boards:  ['a', 'co', 'jp', 'm', 'q', 'sp', 'tg', 'tv', 'v', 'vg', 'wsg', 'dev', 'foolz']
      type:    'foolfuuka'
    'NSFWFoolz':
      base:    '//nsfw.foolz.us'
      boards:  ['u', 'kuku']
      type:    'foolfuuka'
    'TheDarkCave':
      base:    'http://archive.thedarkcave.org'
      boards:  ['c', 'int', 'po']
      type:    'foolfuuka'
    'Warosu':
      base:    '//fuuka.warosu.org'
      boards:  ['cgl', 'ck', 'jp', 'lit', 'q', 'tg']
      type:    'fuuka'
    'RebeccaBlackTech':
      base:    '//rbt.asia'
      boards:  ['cgl', 'g', 'mu', 'w']
      type:    'fuuka_mail'
    'InstallGentoo':
      base:    '//archive.installgentoo.net'
      boards:  ['diy', 'g', 'sci']
      type:    'fuuka'
    'Heinessen':
      base:    'http://archive.heinessen.com'
      boards:  ['an', 'fit', 'k', 'mlp', 'r9k', 'toy', 'x']
      type:    'fuuka'
    'Cliché':
      base: '//www.xn--clich-fsa.net/4chan/cgi-board.pl'
      boards: ['e']
      type: 'fuuka'
    'NyaFuu':
      base: '//archive.nyafuu.org'
      boards: ['c', 'w']
      type: 'fuuka'

  select: (board) ->
    return (name for name, archive of @archiver when archive.boards.contains board or g.BOARD)

  to: (data) ->
    {board, threadID, isSearch} = data

    return (if archive = @archiver[$.get "archiver/#{board}/", @select(board)[0]]
      @path archive.base, archive.type, data
    else if threadID and not isSearch
      "//boards.4chan.org/#{board}/"
    else
      null)

  path: (base, archiver, data) ->
    {board, type, value, threadID, postID, isSearch} = data
    if isSearch
      type = if type is 'name'
        'username'
      else if type is 'md5'
        'image'
      else
        type
      value = encodeURIComponent value
      return (if (url = if archiver is 'foolfuuka'
        "search/#{type}/"
      else if type is 'image'
        "?task=search2&search_media_hash="
      else if type isnt 'email' or archiver is 'fuuka_mail'
        "?task=search2&search_#{type}="
      else
        false
      ) then "#{base}/#{board}/#{url}#{value}" else url)
    # keep the number only if the location.hash was sent f.e.
    postID = postID.match(/\d+/)[0] if postID
    return base + "/" + board + "/" + (
      if threadID
        "thread/#{threadID}"
      else
        "post/#{postID}"
    ) + (
      if threadID and postID
        "##{if archiver is 'foolfuuka' then 'p' else ''}#{postID}"
      else ""
    )

ImageHover =
  init: ->
    Main.callbacks.push @node
  node: (post) ->
    return if (!post.img or post.hasPDF)
    $.on post.img, 'mouseover', ImageHover.mouseover
  mouseover: ->
    # Make sure to remove the previous image hover
    # in case it got stuck. Opera-only bug?
    if el = $.id 'ihover'
      if el is UI.el
        delete UI.el
      $.rm el

    # Don't stop other elements from dragging
    return if UI.el

    el = UI.el = $.el 'img'
      id: 'ihover'
      src: @parentNode.href
    $.add d.body, el
    $.on el, 'load',      ImageHover.load
    $.on el, 'error',     ImageHover.error
    $.on @,  'mousemove', UI.hover
    $.on @,  'mouseout',  ImageHover.mouseout
  load: ->
    return unless @parentNode
    # 'Fake' mousemove event by giving required values.
    {style} = @
    UI.hover
      clientX: - 45 + parseInt style.left
      clientY:  120 + parseInt style.top
  error: ->
    src = @src.split '/'
    unless src[2] is 'images.4chan.org' and url = Redirect.image src[3], src[5]
      return if g.dead
      url = "//images.4chan.org/#{src[3]}/src/#{src[5]}"
    return if $.engine isnt 'webkit' and url.split('/')[2] is 'images.4chan.org'
    timeoutID = setTimeout (=> @src = url), 3000
    # Only Chrome let userscripts do cross domain requests.
    # Don't check for 404'd status in the archivers.
    return if $.engine isnt 'webkit' or url.split('/')[2] isnt 'images.4chan.org'
    $.ajax url, onreadystatechange: (-> clearTimeout timeoutID if @status is 404),
      type: 'head'
  mouseout: ->
    UI.hoverend()
    $.off @, 'mousemove', UI.hover
    $.off @, 'mouseout',  ImageHover.mouseout

Prefetch =
  init: ->
    return if g.BOARD is 'f'
    @dialog()
  dialog: ->
    controls = $.el 'label',
      id: 'prefetch'
      innerHTML:
        "<input type=checkbox>Prefetch Images"
    input = $ 'input', controls
    $.on input, 'change', Prefetch.change

    first = $.id('delform').firstElementChild
    if first.id is 'imgControls'
      $.after first, controls
    else
      $.before first, controls
    Style.rice controls

  change: ->
    $.off @, 'change', Prefetch.change
    for thumb in $$ 'a.fileThumb'
      $.el 'img',
        src: thumb.href
    Main.callbacks.push Prefetch.node

  node: (post) ->
    {img} = post
    return if post.el.hidden or not img
    $.el 'img',
      src: img.parentNode.href

ImageReplace =
  init: ->
    return if g.BOARD is 'f'
    Main.callbacks.push @node

  node: (post) ->
    {img} = post
    return if post.el.hidden or !img or /spoiler/.test img.src
    if Conf["Replace #{if (type = ((href = img.parentNode.href).match /\w{3}$/)[0].toUpperCase()) is 'PEG' then 'JPG' else type}"]
      el = $.el 'img'
      el.setAttribute 'data-id', post.ID
      $.on el, 'load', ->
        img.src = el.src
      el.src = href


ImageExpand =
  init: ->
    return if g.BOARD is 'f'
    Main.callbacks.push @node
    @dialog()

  node: (post) ->
    return if (!post.img or post.hasPDF)
    a = post.img.parentNode
    $.on a, 'click', ImageExpand.cb.toggle

    # Detect Spoilers in this post.
    return if Conf['Don\'t Expand Spoilers'] and !Conf['Reveal Spoilers'] and /^spoiler\ image/i.test a.firstChild.alt

    # Expand the image if "Expand All" is enabled.
    if ImageExpand.on and !post.el.hidden
      ImageExpand.expand post.img

  cb:
    toggle: (e) ->
      return if e.shiftKey or e.altKey or e.ctrlKey or e.metaKey or e.button
      e.preventDefault()
      ImageExpand.toggle @

    all: ->
      ImageExpand.on = @checked
      if ImageExpand.on # Expand
        thumbs = $$ 'img[data-md5]'
        if Conf['Expand From Current']
          for thumb, i in thumbs
            break if thumb.getBoundingClientRect().top > 0
          thumbs = thumbs[i...]
        for thumb in thumbs
          continue if Conf['Don\'t Expand Spoilers'] and !Conf['Reveal Spoilers'] and /^spoiler\ image/i.test thumb.alt
          ImageExpand.expand thumb
      else # Contract
        for thumb in $$ 'img[data-md5][hidden]'
          ImageExpand.contract thumb
      return

    typeChange: ->
      klass = switch @value
        when 'full'
          ''
        when 'fit width'
          'fitwidth'
        when 'fit height'
          'fitheight'
        when 'fit screen'
          'fitwidth fitheight'
      $.id('delform').className = klass
      if /\bfitheight\b/.test klass
        $.on window, 'resize', ImageExpand.resize
        unless ImageExpand.style
          ImageExpand.style = $.addStyle ''
        ImageExpand.resize()
      else if ImageExpand.style
        $.off window, 'resize', ImageExpand.resize

  toggle: (a) ->
    thumb = a.firstChild
    if thumb.hidden
      rect = a.getBoundingClientRect()
      if rect.bottom > 0 # should be at least partially visible.
        # Scroll back to the thumbnail when contracting the image
        # to avoid being left miles away from the relevant post.
        if $.engine is 'webkit'
          d.body.scrollTop  += rect.top - 42 if rect.top < 0
          d.body.scrollLeft += rect.left     if rect.left < 0
        else
          d.documentElement.scrollTop  += rect.top - 42 if rect.top < 0
          d.documentElement.scrollLeft += rect.left     if rect.left < 0
      ImageExpand.contract thumb
    else
      ImageExpand.expand thumb

  contract: (thumb) ->
    thumb.hidden = false
    thumb.nextSibling.hidden = true
    $.rmClass thumb.parentNode.parentNode.parentNode.parentNode, 'image_expanded'

  expand: (thumb, src) ->
    # Do not expand images of hidden/filtered replies, or already expanded pictures.
    return if $.x 'ancestor-or-self::*[@hidden]', thumb
    a = thumb.parentNode
    src or= a.href
    return if /\.pdf$/.test src
    thumb.hidden = true
    $.addClass thumb.parentNode.parentNode.parentNode.parentNode, 'image_expanded'
    if (img = thumb.nextSibling) and img.tagName.toLowerCase() is 'img'
      # Expand already loaded picture
      img.hidden = false
      return
    img = $.el 'img'
      src:       src
      className: 'fullSize'
    $.on img, 'error', ImageExpand.error
    $.after thumb, img

  error: ->
    thumb = @previousSibling
    ImageExpand.contract thumb
    $.rm @
    src = @src.split '/'
    unless src[2] is 'images.4chan.org' and url = Redirect.image src[3], src[5]
      return if g.dead
      url = "//images.4chan.org/#{src[3]}/src/#{src[5]}"
    return if $.engine isnt 'webkit' and url.split('/')[2] is 'images.4chan.org'
    timeoutID = setTimeout ImageExpand.expand, 10000, thumb, url
    # Only Chrome let userscripts do cross domain requests.
    # Don't check for 404'd status in the archivers.
    return if $.engine isnt 'webkit' or url.split('/')[2] isnt 'images.4chan.org'
    $.ajax url, onreadystatechange: (-> clearTimeout timeoutID if @status is 404),
      type: 'head'

  dialog: ->
    controls = $.el 'div',
      id: 'imgControls'
      innerHTML:
        "<div id=imgContainer><select id=imageType name=imageType><option value=full>Full</option><option value='fit width'>Fit Width</option><option value='fit height'>Fit Height</option value='fit screen'><option value='fit screen'>Fit Screen</option></select><label><input type=checkbox id=imageExpand></label></div>"
    imageType = $.get 'imageType', 'full'
    select = $ 'select', controls
    select.value = imageType
    ImageExpand.cb.typeChange.call select
    $.on select, 'change', $.cb.value
    $.on select, 'change', ImageExpand.cb.typeChange
    $.on $('input', controls), 'click', ImageExpand.cb.all
    Style.rice controls

    $.prepend $.id('delform'), controls

  resize: ->
    ImageExpand.style.textContent = ".fitheight img[data-md5] + img {max-height:#{d.documentElement.clientHeight}px;}"

CatalogLinks =
  init: ->
    el = $.el 'span',
      id:        'toggleCatalog'
      innerHTML: '[<a href=javascript:;></a>]'
    $.on (a = el.firstElementChild), 'click', @toggle
    $.add $.id('boardNavDesktop'), el

    # Set links on load.
    @toggle.call a, true

  toggle: (onLoad) ->
    if onLoad is true
      useCatalog = $.get 'CatalogIsToggled', g.CATALOG
    else
      $.set 'CatalogIsToggled', useCatalog = @textContent is 'Catalog Off'
    for a in $$ 'a', $.id('boardNavDesktop')
      board = a.pathname.split('/')[1]
      if ['f', 'status', '4chan'].contains(board) or !board
        if board is 'f'
          a.pathname = '/f/'
        continue
      if Conf['External Catalog']
        a.href = if useCatalog
          CatalogLinks.external(board)
        else
          "//boards.4chan.org/#{board}/"
      else
        a.pathname = "/#{board}/#{if useCatalog then 'catalog' else ''}"
      a.title = if useCatalog then "#{a.title} - Catalog" else a.title.replace(/\ -\ Catalog$/, '')
    @textContent = "Catalog #{if useCatalog then 'On' else 'Off'}"
    @title       = "Turn catalog links #{if useCatalog then 'off' else 'on'}."

  external: (board) ->
    return (
      if ['a', 'c', 'g', 'co', 'k', 'm', 'o', 'p', 'v', 'vg', 'w', 'cm', '3', 'adv', 'an', 'cgl', 'ck', 'diy', 'fa', 'fit', 'int', 'jp', 'mlp', 'lit', 'mu', 'n', 'po', 'sci', 'toy', 'trv', 'tv', 'vp', 'x', 'q'].contains board
        "http://catalog.neet.tv/#{board}"
      else if ['d', 'e', 'gif', 'h', 'hr', 'hc', 'r9k', 's', 'pol', 'soc', 'u', 'i', 'ic', 'hm', 'r', 'w', 'wg', 'wsg', 't', 'y'].contains board
        "http://4index.gropes.us/#{board}"
      else
        "//boards.4chan.org/#{board}/catalog"
    )