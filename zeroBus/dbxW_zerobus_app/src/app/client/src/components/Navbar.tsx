import { NavLink } from 'react-router';
import {
  Home,
  FileText,
  Activity,
  Database,
} from 'lucide-react';

const navItems = [
  { to: '/', label: 'Overview', icon: Home, end: true },
  { to: '/health', label: 'Health Status', icon: Activity },
  { to: '/docs', label: 'API Docs', icon: FileText },
  { to: '/lakebase', label: 'Lakebase', icon: Database },
];

const navLinkClass = ({ isActive }: { isActive: boolean }) =>
  `flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-all duration-200 ${
    isActive
      ? 'bg-[var(--dbx-red)] text-white shadow-md shadow-[var(--dbx-red)]/25'
      : 'text-gray-300 hover:text-white hover:bg-white/10'
  }`;

export function Navbar() {
  return (
    <header className="gradient-hero border-b border-white/10 sticky top-0 z-50">
      <div className="max-w-7xl mx-auto px-6 py-3 flex items-center justify-between">
        {/* Logo + Title */}
        <NavLink to="/" className="flex items-center gap-3 group">
          <img
            src="/images/databricks-symbol-light.svg"
            alt="Databricks"
            className="h-8 w-8 group-hover:scale-105 transition-transform"
          />
          <div className="flex flex-col">
            <span className="text-white font-bold text-lg leading-tight tracking-tight">
              dbxWearables
            </span>
            <span className="text-gray-400 text-xs leading-tight">
              ZeroBus Health Data Gateway
            </span>
          </div>
        </NavLink>

        {/* Nav links */}
        <nav className="flex gap-1">
          {navItems.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.end}
              className={navLinkClass}
            >
              <item.icon className="h-4 w-4" />
              {item.label}
            </NavLink>
          ))}
        </nav>
      </div>
    </header>
  );
}
