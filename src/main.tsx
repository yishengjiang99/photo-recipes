import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import App from './App'
import { ErrorBoundary } from './components/ErrorBoundary'
import { SubscriptionProvider } from './hooks/useSubscription'
import './index.css'
import { initAnalytics } from './lib/analytics'

initAnalytics()

const rootEl = document.getElementById('root')!

try {
  createRoot(rootEl).render(
    <StrictMode>
      <ErrorBoundary>
        <BrowserRouter>
          <SubscriptionProvider>
            <App />
          </SubscriptionProvider>
        </BrowserRouter>
      </ErrorBoundary>
    </StrictMode>,
  )
  // Mark boot success so the inline index.html fallback does not overwrite the UI.
  rootEl.dataset.booted = '1'
} catch (err) {
  const msg = err instanceof Error ? err.message : String(err)
  rootEl.innerHTML =
    '<div style="min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:1rem;padding:1.5rem;background:#0c0c0f;color:#f4f4f5;font-family:system-ui,sans-serif;text-align:center">' +
    '<h1 style="font-size:1.25rem;margin:0">Photo Recipes failed to load</h1>' +
    `<p style="margin:0;opacity:.85;max-width:28rem;font-size:.9rem">${msg.slice(0, 280)}</p>` +
    '<p style="margin:0;opacity:.7;max-width:28rem;font-size:.85rem">Clear Safari cache / try Private Tab</p>' +
    '<a href="/" style="margin-top:.5rem;padding:.5rem 1rem;border-radius:8px;background:#3b82f6;color:#fff;text-decoration:none;font-weight:600">Reload</a>' +
    '</div>'
}
