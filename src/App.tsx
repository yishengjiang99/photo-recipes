import { lazy, Suspense } from 'react'
import { Navigate, Route, Routes, useParams } from 'react-router-dom'
import { PricingModal } from './components/PricingModal'
import { Landing } from './pages/Landing'
import { Privacy } from './pages/Privacy'
import { Support } from './pages/Support'
import { Terms } from './pages/Terms'

// The marketing and legal pages ship in the main bundle (they are also pre-rendered at build time);
// the app shell, camera and admin load on demand so the landing page downloads less JavaScript.
const Layout = lazy(() => import('./components/Layout').then((m) => ({ default: m.Layout })))
const Admin = lazy(() => import('./pages/Admin').then((m) => ({ default: m.Admin })))
const CameraPage = lazy(() => import('./pages/Camera').then((m) => ({ default: m.CameraPage })))
const Library = lazy(() => import('./pages/Library').then((m) => ({ default: m.Library })))
const PresetDetail = lazy(() => import('./pages/PresetDetail').then((m) => ({ default: m.PresetDetail })))
const Success = lazy(() => import('./pages/Success').then((m) => ({ default: m.Success })))

function LegacyPresetRedirect() {
  const { id } = useParams<{ id: string }>()
  return <Navigate to={id ? `/app/preset/${id}` : '/app'} replace />
}

export default function App() {
  return (
    <>
      <Suspense fallback={<div className="min-h-dvh bg-bg" aria-busy="true" />}>
      <Routes>
        <Route path="/" element={<Landing />} />
        <Route path="/privacy" element={<Privacy />} />
        <Route path="/terms" element={<Terms />} />
        <Route path="/support" element={<Support />} />
        <Route path="/admin" element={<Admin />} />

        <Route path="/app" element={<Layout />}>
          <Route index element={<CameraPage />} />
          <Route path="library" element={<Library />} />
          <Route path="preset/:id" element={<PresetDetail />} />
          <Route path="success" element={<Success />} />
        </Route>

        {/* Legacy paths from pre-landing routing */}
        <Route path="/preset/:id" element={<LegacyPresetRedirect />} />
        <Route path="/success" element={<Navigate to="/app/success" replace />} />

        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
      </Suspense>
      <PricingModal />
    </>
  )
}
