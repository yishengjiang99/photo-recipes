import { Navigate, Route, Routes } from 'react-router-dom'
import { Layout } from './components/Layout'
import { Library } from './pages/Library'
import { PresetDetail } from './pages/PresetDetail'
import { Success } from './pages/Success'

export default function App() {
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route index element={<Library />} />
        <Route path="preset/:id" element={<PresetDetail />} />
        <Route path="success" element={<Success />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  )
}
