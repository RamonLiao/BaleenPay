interface StatCardProps {
  label: string
  value: string
  sub?: string
}

export function StatCard({ label, value, sub }: StatCardProps) {
  return (
    <div className="rounded-2xl border border-ocean-foam/30 bg-white p-6">
      <p className="text-sm text-ocean-ink mb-1">{label}</p>
      <p className="text-2xl font-bold text-ocean-deep">{value}</p>
      {sub && <p className="text-xs text-ocean-ink mt-1">{sub}</p>}
    </div>
  )
}
