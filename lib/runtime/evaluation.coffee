# TODO: this is very horrible, refactor
path = require 'path'
{dialog, BrowserWindow} = require('electron').remote

{client} =  require '../connection'
{notifications, views, selector, docpane} = require '../ui'
{paths, blocks, cells, words, weave} = require '../misc'
{processLinks} = require '../ui/docs'
workspace = require './workspace'
modules = require './modules'
{eval: evaluate, evalall, evalrepl, evalshow, cd, clearLazy} =
    client.import rpc: ['eval', 'evalall', 'evalrepl', 'evalshow'], msg: ['cd', 'clearLazy']

module.exports =
  _currentContext: ->
    editor = atom.workspace.getActiveTextEditor()
    mod = modules.current() ? 'Main'
    edpath = client.editorPath(editor) || 'untitled-' + editor.getBuffer().id
    {editor, mod, edpath}

  _showError: (r, lines) ->
    @errorLines?.lights.destroy()
    lights = @ink.highlights.errorLines (file: file, line: line-1 for {file, line} in lines)
    @errorLines = {r, lights}
    r.onDidDestroy =>
      if @errorLines?.r == r then @errorLines.lights.destroy()

  eval: ({move, cell}={}) ->
    {editor, mod, edpath} = @_currentContext()
    selector = if cell? then cells else blocks
    Promise.all selector.get(editor).map ({range, line, text, selection}) =>
      selector.moveNext editor, selection, range if move
      [[start], [end]] = range
      @ink.highlight editor, start, end
      rtype = if cell? then "block" else atom.config.get 'julia-client.uiOptions.resultsDisplayMode'
      if rtype is 'console'
        if atom.config.get('julia-client.consoleOptions.consoleStyle') is 'REPL-based'
          evalshow({text, line: line+1, mod, path: edpath})
        else
          evalrepl(code: text, mod: mod)
            .then (result) => workspace.update()
            .catch =>
      else
        r = null
        setTimeout (=> r ?= new @ink.Result editor, [start, end], {type: rtype, scope: 'julia'}), 0.1
        evaluate({text, line: line+1, mod, path: edpath})
          .catch -> r?.destroy()
          .then (result) =>
            if not result?
              r?.destroy()
              console.error 'Error: Something went wrong while evaluating.'
              return
            error = result.type == 'error'
            view = if error then result.view else result
            if not r? or r.isDestroyed then r = new @ink.Result editor, [start, end], {type: rtype, scope: 'julia'}
            registerLazy = (id) ->
              r.onDidDestroy client.withCurrent -> clearLazy [id]
              editor.onDidDestroy client.withCurrent -> clearLazy id
            r.setContent views.render(view, {registerLazy}), {error}
            if error and result.highlights?
              @_showError r, result.highlights
            atom.beep() if error
            notifications.show "Evaluation Finished"
            workspace.update()
            result

  evalAll: ->
    {editor, mod, edpath} = @_currentContext()
    atom.commands.dispatch atom.views.getView(editor), 'inline-results:clear-all'
    [scope] = editor.getRootScopeDescriptor().getScopesArray()
    weaveScopes = ['source.weave.md', 'source.weave.latex']
    module = if weaveScopes.includes scope then mod else editor.juliaModule
    code = if weaveScopes.includes scope then weave.getCode editor else editor.getText()
    evalall({
      path: edpath
      module: module
      code: code
    }).then (result) ->
      notifications.show "Evaluation Finished"
      workspace.update()

  provideHyperclick: () ->
    {
      providerName: 'julia-client-hyperclick-provider'
      grammarScopes: atom.config.get('julia-client.juliaSyntaxScopes')
      wordRegExp:  new RegExp(words.wordRegex, "g")
      getSuggestionForWord: (editor, text, range) =>
        require('../connection').boot()
        {
          range: range
          callback: => @gotoSymbol(text, range)
        }
    }

  gotoSymbol: (word, range) ->
    {editor, mod, edpath} = @_currentContext()
    {word, range} = words.getWord(editor) unless word? and range?
    if word.length == 0 || !isNaN(word) then return
    client.import("methods")({word: word, mod: mod}).then (symbols) =>
      @ink.goto.goto symbols unless symbols.error

  toggleDocs: (word, range) ->
    {editor, mod, edpath} = @_currentContext()
    {word, range} = words.getWord(editor) unless word? and range?
    if word.length == 0 || !isNaN(word) then return
    client.import("docs")({word: word, mod: mod}).then (result) =>
      if result.error then return
      v = views.render result
      processLinks(v.getElementsByTagName('a'))
      if atom.config.get('julia-client.uiOptions.docsDisplayMode') == 'inline'
        d = new @ink.InlineDoc editor, range,
          content: v
          highlight: true
        d.view.classList.add 'julia'
      else
        docpane.ensureVisible()
        docpane.showDocument(v, [])

  # Working Directory

  _cd: (dir) ->
    if atom.config.get('julia-client.juliaOptions.persistWorkingDir')
      atom.config.set('julia-client.juliaOptions.workingDir', dir)
    cd(dir)

  cdHere: ->
    file = client.editorPath(atom.workspace.getActiveTextEditor())
    if !file then atom.notifications.addError 'This file has no path.'
    @_cd path.dirname(file)

  cdProject: ->
    dirs = atom.project.getPaths()
    if dirs.length < 1
      atom.notifications.addError 'This project has no folders.'
    else if dirs.length == 1
      @_cd dirs[0]
    else
      selector.show(dirs).then (dir) =>
        return unless dir?
        @_cd dir

  cdHome: ->
    @_cd paths.home()

  cdSelect: ->
    opts = properties: ['openDirectory']
    dialog.showOpenDialog BrowserWindow.getFocusedWindow(), opts, (path) =>
      if path? then @_cd path[0]
