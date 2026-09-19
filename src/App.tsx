import { Navigate, Route, Routes, useParams } from 'react-router-dom'
import { Layout } from './components/Layout'
import { PricingModal } from './components/PricingModal'
import { Landing } from './pages/Landing'
import { Library } from './pages/Library'
import { PresetDetail } from './pages/PresetDetail'
import { Success } from './pages/Success'

function LegacyPresetRedirect() {
  const { id } = useParams<{ id: string }>()
  return <Navigate to={id ? `/app/preset/${id}` : '/app'} replace />
}

export default function App() {
  return (
    <>
      <Routes>
        <Route path="/" element={<Landing />} />

        <Route path="/app" element={<Layout />}>
          <Route index element={<Library />} />
          <Route path="preset/:id" element={<PresetDetail />} />
          <Route path="success" element={<Success />} />
        </Route>

        {/* Legacy paths from pre-landing routing */}
        <Route path="/preset/:id" element={<LegacyPresetRedirect />} />
        <Route path="/success" element={<Navigate to="/app/success" replace />} />

        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
      {/* Shared paywall so landing CTAs and app Upgrade both work */}
      <PricingModal />
    </>
  )
}
