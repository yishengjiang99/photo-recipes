import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import App from './App'
import { SubscriptionProvider } from './hooks/useSubscription'
import './index.css'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <BrowserRouter>
      <SubscriptionProvider>
        <App />
      </SubscriptionProvider>
    </BrowserRouter>
  </StrictMode>,
)
