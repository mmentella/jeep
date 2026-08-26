import type { JeepNotebookApi } from '../../preload'

declare global {
  interface Window {
    jeepNotebook: JeepNotebookApi
  }
}

export {}
