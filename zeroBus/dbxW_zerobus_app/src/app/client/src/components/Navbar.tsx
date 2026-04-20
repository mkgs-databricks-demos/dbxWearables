import { NavLink } from 'react-router';
import { Home } from 'lucide-react';
import { BrandIcon } from '@/components/BrandIcon';
import { ThemeToggle } from '@/components/ThemeToggle';

type NavItem = {
  to: string;
  label: string;
  end?: boolean;
} & (
  | { kind: 'lucide'; icon: React.ComponentType<{ className?: string }> }
  | { kind: 'brand'; brandKey: import('@/icons').IconKey }
);

const navItems: NavItem[] = [
  { to: '/', label: 'Overview', kind: 'lucide', icon: Home, end: true },
  { to: '/status', label: 'Health Status', kind: 'brand', brandKey: 'healthcare-white' },
  { to: '/docs', label: 'API Docs', kind: 'brand', brandKey: 'endpoint' },
  { to: '/security', label: 'Security', kind: 'brand', brandKey: 'data-security' },
];

const navLinkClass = ({ isActive }: { isActive: boolean }) =>
  `flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-all duration-200 ${
    isActive
      ? 'bg-[var(--dbx-lava-600)] text-white shadow-md shadow-[var(--dbx-lava-600)]/25'
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

        {/* Nav links + Theme toggle */}
        <div className="flex items-center gap-1">
          <nav className="flex gap-1">
            {navItems.map((item) => (
              <NavLink
                key={item.to}
                to={item.to}
                end={item.end}
                className={navLinkClass}
              >
                {item.kind === 'lucide'
                ? <item.icon className="h-4 w-4" />
                : <BrandIcon name={item.brandKey} className="h-4 w-4" />
              }
                {item.label}
              </NavLink>
            ))}
          </nav>
          <div className="ml-2 border-l border-white/20 pl-2">
            <ThemeToggle />
          </div>
        </div>
      </div>
    </header>
  );
}
