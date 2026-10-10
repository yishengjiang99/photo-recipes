// Build-time prerender entry (scripts/prerender.mjs). Renders the public, crawlable routes to static
// HTML so search engines and link previews see real content and per-page head tags before JS runs.
import { renderToStaticMarkup } from 'react-dom/server'
import { StaticRouter } from 'react-router-dom'
import App from '../src/App'
import { ssrHead } from '../src/components/Seo'
import { SubscriptionProvider } from '../src/hooks/useSubscription'

export function render(url: string) {
  ssrHead.current = null
  const html = renderToStaticMarkup(
    <StaticRouter location={url}>
      <SubscriptionProvider>
        <App />
      </SubscriptionProvider>
    </StaticRouter>,
  )
  return { html, head: ssrHead.current }
}
