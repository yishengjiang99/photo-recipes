import { Navigate, Route, Routes, useParams } from 'react-router-dom'
import { Layout } from './components/Layout'
import { PricingModal } from './components/PricingModal'
import { Admin } from './pages/Admin'
import { CameraPage } from './pages/Camera'
import { Landing } from './pages/Landing'
import { Library } from './pages/Library'
import { PresetDetail } from './pages/PresetDetail'
import { Privacy } from './pages/Privacy'
import { Success } from './pages/Success'
import { Support } from './pages/Support'
import { Terms } from './pages/Terms'

function LegacyPresetRedirect() {
  const { id } = useParams<{ id: string }>()
  return <Navigate to={id ? `/app/preset/${id}` : '/app'} replace />
}

export default function App() {
  return (
    <>
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
      <PricingModal />
    </>
  )
}
