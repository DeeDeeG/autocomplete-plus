_ = require 'underscore-plus'
SimpleSelectListView = require './simple-select-list-view'
{Editor, $, $$, Range, SelectListView}  = require 'atom'

module.exports =
class AutocompleteView extends SimpleSelectListView
  currentBuffer: null
  wordList: null
  wordRegex: /\w+/g
  originalSelectionBufferRange: null
  originalCursorPosition: null
  aboveCursor: false

  initialize: (@editorView) ->
    super
    @addClass('autocomplete popover-list')
    {@editor} = @editorView

    @handleEvents()
    @setCurrentBuffer(@editor.getBuffer())

  ###
   * Creates a view for the given item
  ###
  viewForItem: ({word}) ->
    $$ ->
      @li =>
        @span word

  ###
   * Handles editor events
  ###
  handleEvents: ->
    @list.on 'mousewheel', (event) -> event.stopPropagation()

    @editorView.on 'editor:path-changed', => @setCurrentBuffer(@editor.getBuffer())

    @editor.on 'contents-modified', => @contentsModified()
    @editorView.command 'autocomplete:next', => @selectNextItemView()
    @editorView.command 'autocomplete:previous', => @selectPreviousItemView()

  ###
   * Return false so that the events don't bubble up to the editor
  ###
  selectNextItemView: ->
    super
    false

  ###
   * Return false so that the events don't bubble up to the editor
  ###
  selectPreviousItemView: ->
    super
    false

  ###
   * Don't really know what that does...
  ###
  getCompletionsForCursorScope: ->
    cursorScope = @editor.scopesForBufferPosition(@editor.getCursorBufferPosition())
    completions = atom.syntax.propertiesForScope(cursorScope, 'editor.completions')
    completions = completions.map (properties) -> _.valueForKeyPath(properties, 'editor.completions')
    _.uniq(_.flatten(completions))

  ###
   * Generates the word list from the editor buffer(s)
  ###
  buildWordList: ->
    wordHash = {}
    if atom.config.get('autocomplete.includeCompletionsFromAllBuffers')
      buffers = atom.project.getBuffers()
    else
      buffers = [@currentBuffer]
    matches = []
    matches.push(buffer.getText().match(@wordRegex)) for buffer in buffers
    wordHash[word] ?= true for word in _.flatten(matches)
    wordHash[word] ?= true for word in @getCompletionsForCursorScope()

    @wordList = Object.keys(wordHash).sort (word1, word2) ->
      word1.toLowerCase().localeCompare(word2.toLowerCase())

  ###
   * Handles confirmation (the user pressed enter)
  ###
  confirmed: (match) ->
    @editor.getSelection().clear()

    @cancel()
    return unless match
    @replaceTextWithMatch match
    position = @editor.getCursorBufferPosition()
    @editor.setCursorBufferPosition([position.row, position.column])

  ###
   * Clears the list, sets back the cursor, focuses the editor and
   * detaches the list DOM element
  ###
  cancel: ->
    @list.empty()

    @editor.abortTransaction()
    @editor.setSelectedBufferRange(@originalSelectionBufferRange)
    @editorView.focus()

    @detach()

  contentsModified: ->
    @buildWordList()

    selection = @editor.getSelection()
    prefix = @prefixOfSelection selection

    # No prefix? Don't autocomplete!
    return unless prefix.length

    suggestions = @findMatchesForWord prefix

    # No suggestions? Don't autocomplete!
    return unless suggestions.length

    # Now we're ready - display the suggestions
    @editor.beginTransaction()

    @originalSelectionBufferRange = @editor.getSelection().getBufferRange()
    @originalCursorPosition = @editor.getCursorScreenPosition()

    @setItems suggestions
    @editorView.appendToLinesView this
    @setPosition()

    @setActive()

  findMatchesForWord: (prefix) ->
    regex = new RegExp "^#{prefix}.+$", "i"
    for word in @wordList when regex.test(word) and word isnt prefix
      {prefix, word}

  setPosition: ->
    { left, top } = @editorView.pixelPositionForScreenPosition(@originalCursorPosition)
    height = @outerHeight()
    potentialTop = top + @editorView.lineHeight
    potentialBottom = potentialTop - @editorView.scrollTop() + height

    if @aboveCursor or potentialBottom > @editorView.outerHeight()
      @aboveCursor = true
      @css(left: left, top: top - height, bottom: 'inherit')
    else
      @css(left: left, top: potentialTop, bottom: 'inherit')

  ###
   * Replaces the current prefix with the given match
  ###
  replaceTextWithMatch: (match) ->
    selection = @editor.getSelection()
    startPosition = selection.getBufferRange().start
    buffer = @editor.getBuffer()

    selection.deleteSelectedText()
    cursorPosition = @editor.getCursorBufferPosition()
    buffer.delete(Range.fromPointWithDelta(cursorPosition, 0, -match.prefix.length))
    @editor.insertText(match.word)

    infixLength = match.word.length - match.prefix.length
    @editor.setSelectedBufferRange([startPosition, [startPosition.row, startPosition.column + infixLength]])

  ###
   * Finds and returns the content before the current cursor position
  ###
  prefixOfSelection: (selection) ->
    selectionRange = selection.getBufferRange()
    lineRange = [[selectionRange.start.row, 0], [selectionRange.end.row, @editor.lineLengthForBufferRow(selectionRange.end.row)]]
    prefix = ""

    @currentBuffer.scanInRange @wordRegex, lineRange, ({match, range, stop}) ->
      stop() if range.start.isGreaterThan(selectionRange.end)

      if range.intersectsWith(selectionRange)
        prefixOffset = selectionRange.start.column - range.start.column
        prefix = match[0][0...prefixOffset] if range.start.isLessThan(selectionRange.start)

    return prefix

  ###
   * As soon as the list is in the DOM tree, it calculates the
   * maximum width of all list items and resizes the list so that
   * all items fit
   *
   * @todo: Fix this. Doesn't work well yet.
  ###
  afterAttach: (onDom) ->
    if onDom
      widestCompletion = parseInt(@css('min-width')) or 0
      @list.find('span').each ->
        widestCompletion = Math.max(widestCompletion, $(this).outerWidth())
      @list.width(widestCompletion + 20)
      @width(@list.outerWidth())

  ###
   * Updates the list's position when populating results
  ###
  populateList: ->
    super

    @setPosition()

  ###
   * Sets the current buffer
  ###
  setCurrentBuffer: (@currentBuffer) -> return

  ###
   * Defines which key we would like to use for filtering
  ###
  getFilterKey: -> 'word'
