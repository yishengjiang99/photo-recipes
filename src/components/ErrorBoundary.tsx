import { Component, type ErrorInfo, type ReactNode } from 'react'

type Props = { children: ReactNode }
type State = { error: Error | null }

/**
 * Catches boot/render crashes so users see a message instead of a blank page.
 */
export class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null }

  static getDerivedStateFromError(error: Error): State {
    return { error }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('App ErrorBoundary:', error, info.componentStack)
  }

  render() {
    if (this.state.error) {
      return (
        <div
          style={{
            minHeight: '100vh',
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            gap: '1rem',
            padding: '1.5rem',
            background: '#0c0c0f',
            color: '#f4f4f5',
            fontFamily: 'system-ui, sans-serif',
            textAlign: 'center',
          }}
        >
          <h1 style={{ fontSize: '1.25rem', margin: 0 }}>Something went wrong</h1>
          <p style={{ margin: 0, opacity: 0.8, maxWidth: '28rem' }}>
            Photo Recipes failed to load. Try a hard refresh (Ctrl/Cmd+Shift+R). If it
            keeps happening, the latest deploy may still be caching — wait a moment and
            try again.
          </p>
          <pre
            style={{
              margin: 0,
              maxWidth: '36rem',
              overflow: 'auto',
              padding: '0.75rem 1rem',
              background: '#18181b',
              borderRadius: 8,
              fontSize: '0.75rem',
              textAlign: 'left',
              color: '#fca5a5',
            }}
          >
            {this.state.error.message}
          </pre>
          <button
            type="button"
            onClick={() => window.location.reload()}
            style={{
              marginTop: '0.5rem',
              padding: '0.5rem 1rem',
              borderRadius: 8,
              border: 'none',
              background: '#3b82f6',
              color: '#fff',
              cursor: 'pointer',
              fontWeight: 600,
            }}
          >
            Reload
          </button>
        </div>
      )
    }
    return this.props.children
  }
}
