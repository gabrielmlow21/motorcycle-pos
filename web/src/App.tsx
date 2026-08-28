import { useEffect, useState } from 'react'

import './App.css'

type ApiStatus = 'checking' | 'ok' | 'unreachable'

const apiUrl = import.meta.env.VITE_API_URL as string | undefined

function App() {
  const [apiStatus, setApiStatus] = useState<ApiStatus>(apiUrl ? 'checking' : 'unreachable')

  useEffect(() => {
    if (!apiUrl) return

    const controller = new AbortController()

    fetch(`${apiUrl}/up`, { signal: controller.signal })
      .then((response) => setApiStatus(response.ok ? 'ok' : 'unreachable'))
      .catch(() => setApiStatus('unreachable'))

    return () => controller.abort()
  }, [])

  return (
    <main className="app-shell">
      <h1>Motorcycle Shop POS</h1>
      <p>API status: {apiStatus}</p>
    </main>
  )
}

export default App
