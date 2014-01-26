class window.KeyEvent
  [disableVrome, passNextKey, currentKeys, keyTimes, bindings] = [false, false, '', 0, {}]

  @init: =>
    for disabledSite in Option.get('disablesites').split(',') when disabledSite isnt ''
      @disable() if new RegExp(disabledSite, 'i').test(location.href)

    document.addEventListener 'keydown', KeyEvent.exec, true

  @add: (keys, func, insertMode) ->
    bindings[keys] ?= [null, null]
    bindings[keys][Number insertMode] = func

  @stopPropagation: (e) ->
    e.stopPropagation()
    e.preventDefault()

  @enable: =>
    [disableVrome, passNextKey] = [false, false]
    Post action: 'Vrome.enable'
    @reset()

  @disable: ->
    if Option.get 'show_disabled_text'
      CmdBox.set title: ' -- PASS THROUGH -- ', mouseOverTitle: CmdBox.remove
    disableVrome = true
    Post action: 'Vrome.disable'
  desc @disable, 'Disable Vrome'
  @disable.options =
    disablesites:
      description: "Disable Vrome in those sites. Multiple URLs can be separated with ','"
      example:     'set disablesites=mail.google.com,reader.google.com'
    enable_vrome_key:
      description: 'Key to enable Vrome again'
      example:     'set enable_vrome_key=<Esc>'
    show_disabled_text:
      description: 'Show Vrome Disabled text or not. You could also know this from the Action Icon'
      example:     'set show_disable_text=0'

  @passNextKey: ->
    CmdBox.set title: ' -- PASS THROUGH (next) -- ', timeout: 2000 if Option.get 'show_disabled_text'
    passNextKey = true
    Post action: 'Vrome.disable'
  desc @passNextKey, 'Pass next key'

  @reset: ->
    CmdBox.remove()
    [currentKeys, times] = ['', 0]

  @times: (onlyRead) ->
    result = keyTimes
    keyTimes = 0 unless onlyRead
    result

  storeLast = (currentKeys, times=0) ->
    Settings.add { currentKeys, times }

  @runLast: ->
    runCurrentKeys Settings.get('@currentKeys'), false
  desc @runLast, 'Repeat the last command'

  filterKey = (key, insertMode) ->
    configure = Settings.get '@configure'
    mode = if insertMode then 'imap' else 'map'
    return key if /^\d$/.test key
    configure?[mode]?[key] or key

  ignoreKey = (key, insertMode) ->
    configure = Settings.get '@configure'
    mode = if insertMode then 'iunmap' else 'unmap'
    configure?[mode]?[key]?

  showStatusLine = ->
    if Option.get 'showstatus'
      CmdBox.set title: "#{keyTimes or ''}#{currentKeys}", timeout: 500

  runCurrentKeys = (keys, insertMode, e) =>
    return unless keys
    key = if e then getKey e else null

    # when run last command, fix run time.
    if key is '.' and not insertMode
      lastTimes = Settings.get '@times'
      keyTimes = (lastTimes or 1) * (keyTimes or 1)
    else
      lastTimes = keyTimes

    # 0 is a special command: could be used to scroll left, also could be used as run count.
    if keyTimes <= 0 or not /^\d$/.test keys
      /^(\d*)(.+)$/.test keys
      count = RegExp.$1
      match = RegExp.$2

      bindingFunction = bindings[match]?[Number insertMode]
      if bindingFunction?
        # Run matched function
        someFunctionCalled = true

        # map j 3j
        mapTimes = Number count
        keyTimes = mapTimes * (keyTimes or 1) if mapTimes > 0

        try
          bindingFunction.call e
        catch err
          Debug err

        keyTimes = lastTimes if mapTimes > 0
      else
        # Check if there are any bindings that match
        for command, modes of bindings when modes[Number insertMode]? and command.startsWith keys
          someBindingMatched = true
          break

    do showStatusLine if not someFunctionCalled and someBindingMatched
    # If any function invoked, then store it to last run command.
    # (Don't do this when run repeat last command or In InsertMode)
    storeLast keys, keyTimes if someFunctionCalled and e and key isnt '.' and not insertMode

    # Reset currentKeys if nothing match or some function called
    currentKeys = '' if someFunctionCalled or not someBindingMatched

    # Set the count time
    keyTimes = keyTimes * 10 + Number(key) if not someFunctionCalled and not insertMode and /^\d$/.test key

    # If some function invoked and a key pressed, reset the count
    # but don't reset it if no key pressed, this should means the function is invoked by runLastCommand.
    keyTimes = 0 if someFunctionCalled and key

    # stopPropagation if Vrome is enabled and any functions executed but not in InsertMode or on a link
    if e and someFunctionCalled and not (isAcceptKey(key) and (insertMode or Hint.isHintable(document.activeElement)))
      @stopPropagation e
    # Compatible with google's new interface
    if e and key?.length is 1 and not insertMode
      @stopPropagation e

  @exec: (e) =>
    key = getKey e
    insertMode = e.target.nodeName in ['INPUT', 'TEXTAREA', 'SELECT'] or e.target.getAttribute('contenteditable')?

    # If Vrome in pass-next or disabled mode and using <C-Esc> to enable it.
    return @enable() if not insertMode and (passNextKey or (disableVrome and isCtrlEscapeKey(key)))
    return @stopPropagation e if key in ['Control', 'Alt', 'Shift']
    return if disableVrome

    currentKeys = filterKey currentKeys.concat(key), insertMode
    return if ignoreKey currentKeys, insertMode

    runCurrentKeys currentKeys, insertMode, e
