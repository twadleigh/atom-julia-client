'use babel'

import { client } from '../connection'
import { CompositeDisposable } from 'atom'
const views = require('./views')

const { searchdocs, methods, moduleinfo, regenerateCache } =
      client.import({rpc: ['searchdocs', 'methods', 'moduleinfo'], msg: ['regenerateCache']})

let ink, subs, pane

export function activate(_ink) {
  ink = _ink

  pane = ink.DocPane.fromId('Documentation')

  pane.search = (text, mod, exportedOnly, allPackages, nameOnly) => {
    client.boot()
    return new Promise((resolve) => {
      searchdocs({query: text, mod, exportedOnly, allPackages, nameOnly}).then((res) => {
        if (!res.error) {
          for (let i = 0; i < res.items.length; i += 1) {
            res.items[i].score = res.scores[i]
            res.items[i] = processItem(res.items[i])
          }
        }
        resolve(res)
      })
    })
  }

  subs = new CompositeDisposable()
  subs.add(atom.commands.add('atom-workspace', 'julia-client:open-documentation-browser', open))
  subs.add(atom.commands.add('atom-workspace', 'julia-client:regenerate-doc-cache', () => {
    regenerateCache()
  }))
  subs.add(atom.config.observe('julia-client.uiOptions.layouts.documentation.defaultLocation', (defaultLocation) => {
    pane.setDefaultLocation(defaultLocation)
  }))
}

export function open () {
  return pane.open({
    split: atom.config.get('julia-client.uiOptions.layouts.documentation.split')
  })
}
export function ensureVisible () {
  return pane.ensureVisible({
    split: atom.config.get('julia-client.uiOptions.layouts.documentation.split')
  })
}
export function close () {
  return pane.close()
}

function processItem (item) {
  item.html = views.render(item.html)

  processLinks(item.html.getElementsByTagName('a'))

  item.onClickName = () => {
    methods({word: item.name, mod: item.mod}).then((symbols) =>
      ink.goto.goto(symbols))
  }

  item.onClickModule = () => {
    moduleinfo({mod: item.mod}).then(({doc, items}) => {
      items.map((x) => processItem(x))
      showDocument(views.render(doc), items)
    })
  }

  return item
}

export function processLinks (links) {
  for (let i = 0; i < links.length; i++) {
    const link = links[i]
    if (link.attributes['href'].value == '@ref') {
      links[i].onclick = () => pane.kwsearch(link.innerText)
    }
  }
}

export function showDocument (view, items) {
  pane.showDocument(view, items)
}

export function deactivate () {
  subs.dispose()
  subs = null
}
