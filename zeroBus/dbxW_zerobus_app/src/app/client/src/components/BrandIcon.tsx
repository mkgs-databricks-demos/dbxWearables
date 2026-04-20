import { icon } from '@/icons';
import type { IconKey } from '@/icons';

interface BrandIconProps {
  /** Key from the icon registry */
  name: IconKey;
  /** Tailwind size classes (e.g. "h-4 w-4", "h-8 w-8") */
  className?: string;
  /** Alt text for accessibility */
  alt?: string;
}

/**
 * Renders a Databricks Brandfolder SVG icon as an <img>.
 * Drop-in replacement for lucide-react icons in contexts where
 * a brand-specific icon is preferred.
 *
 * Usage:
 *   <BrandIcon name="streaming" className="h-4 w-4" />
 */
export function BrandIcon({ name, className = 'h-4 w-4', alt }: BrandIconProps) {
  return (
    <img
      src={icon(name)}
      alt={alt ?? name.replace(/-/g, ' ')}
      className={className}
      loading="lazy"
      draggable={false}
    />
  );
}
