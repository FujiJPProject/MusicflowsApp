import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'

import {
  BrowserRouter,
  Route,
  Routes,
} from "react-router-dom";

import './index.css'
import App from './App.tsx'

import AuthTestPage
  from "./pages/auth/AuthTestPage.tsx";

import JobTestPage
  from "./pages/jobtest/JobTestPage.tsx";

createRoot(document.getElementById('root')!).render(
  <StrictMode>

    <BrowserRouter>

      <Routes>

        {/* 第1段階 */}
        <Route
          path="/"
          element={<App />}
        />

        {/* 第2段階 */}
        <Route
          path="/auth-test"
          element={<AuthTestPage />}
        />

        {/* SQS / Worker Lambda / S3 疎通確認 */}
        <Route
          path="/jobtest"
          element={<JobTestPage />}
        />

      </Routes>

    </BrowserRouter>

  </StrictMode>,
)
