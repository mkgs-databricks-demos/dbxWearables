import { createBrowserRouter, RouterProvider, Outlet } from 'react-router';
import { Navbar } from '@/components/Navbar';
import { HomePage } from '@/pages/home/HomePage';
import { HealthPage } from '@/pages/health/HealthPage';
import { DocsPage } from '@/pages/docs/DocsPage';
import { LakebasePage } from '@/pages/lakebase/LakebasePage';

function Layout() {
  return (
    <div className="min-h-screen bg-[var(--background)] flex flex-col">
      <Navbar />
      <main className="flex-1">
        <Outlet />
      </main>
      <Footer />
    </div>
  );
}

function Footer() {
  return (
    <footer className="bg-[var(--dbx-navy)] text-gray-400 py-8 px-6">
      <div className="max-w-7xl mx-auto">
        <div className="flex flex-col sm:flex-row items-center justify-between gap-4">
          {/* Logo + branding */}
          <div className="flex items-center gap-4">
            <img
              src="/images/databricks-symbol-light.svg"
              alt="Databricks"
              className="h-7 w-7 opacity-60"
            />
            <div>
              <span className="text-white font-bold text-sm">dbxWearables</span>
              <span className="text-gray-500 text-xs block">ZeroBus Health Data Gateway</span>
            </div>
          </div>

          {/* Links */}
          <div className="flex items-center gap-6 text-xs">
            <a
              href="https://docs.databricks.com/aws/en/ingestion/zerobus-overview/"
              target="_blank"
              rel="noopener noreferrer"
              className="text-gray-400 hover:text-white transition-colors"
            >
              ZeroBus Docs
            </a>
            <a
              href="https://databricks.github.io/appkit/"
              target="_blank"
              rel="noopener noreferrer"
              className="text-gray-400 hover:text-white transition-colors"
            >
              AppKit Docs
            </a>
            <a
              href="https://github.com/databricks/appkit"
              target="_blank"
              rel="noopener noreferrer"
              className="text-gray-400 hover:text-white transition-colors"
            >
              GitHub
            </a>
          </div>
        </div>

        {/* Bottom bar */}
        <div className="mt-6 pt-4 border-t border-white/10 flex items-center justify-between">
          <span className="text-xs text-gray-500">Powered by</span>
          <img
            src="/images/primary-lockup-one-color-white-rgb.svg"
            alt="Databricks"
            className="h-4 opacity-40"
          />
        </div>
      </div>
    </footer>
  );
}

const router = createBrowserRouter([
  {
    element: <Layout />,
    children: [
      { path: '/', element: <HomePage /> },
      { path: '/status', element: <HealthPage /> },
      { path: '/docs', element: <DocsPage /> },
      { path: '/lakebase', element: <LakebasePage /> },
    ],
  },
]);

export default function App() {
  return <RouterProvider router={router} />;
}
