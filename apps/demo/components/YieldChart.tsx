'use client'

import { useState, useMemo } from 'react'
import {
  ResponsiveContainer,
  ComposedChart,
  Line,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
} from 'recharts'
import type { YieldDataPoint } from '@baleenpay/react'

type TimeRange = '7d' | '30d' | 'all'

interface YieldChartProps {
  dataPoints: YieldDataPoint[]
  isLoading: boolean
}

const RANGE_MS: Record<TimeRange, number> = {
  '7d': 7 * 24 * 60 * 60 * 1000,
  '30d': 30 * 24 * 60 * 60 * 1000,
  all: Infinity,
}

export function YieldChart({ dataPoints, isLoading }: YieldChartProps) {
  const [range, setRange] = useState<TimeRange>('30d')

  const filtered = useMemo(() => {
    if (range === 'all') return dataPoints
    const cutoff = Date.now() - RANGE_MS[range]
    return dataPoints.filter((d) => d.timestamp >= cutoff)
  }, [dataPoints, range])

  const chartData = useMemo(
    () =>
      filtered.map((d) => ({
        date: new Date(d.timestamp).toLocaleDateString('en-US', {
          month: 'short',
          day: 'numeric',
        }),
        cumulativeYield: d.cumulativeYield,
        apy: d.apy,
      })),
    [filtered],
  )

  if (isLoading) {
    return (
      <div className="rounded-2xl border border-ocean-foam/30 bg-white p-6 h-80 flex items-center justify-center">
        <p className="text-ocean-ink/60 animate-pulse">Loading yield data...</p>
      </div>
    )
  }

  if (dataPoints.length === 0) {
    return (
      <div className="rounded-2xl border border-ocean-foam/30 bg-white p-6 h-80 flex items-center justify-center">
        <p className="text-ocean-ink/60">No yield data yet</p>
      </div>
    )
  }

  const ranges: TimeRange[] = ['7d', '30d', 'all']

  return (
    <div className="rounded-2xl border border-ocean-foam/30 bg-white p-6">
      {/* Header + Range Selector */}
      <div className="flex items-center justify-between mb-4">
        <h4 className="text-sm font-semibold text-ocean-deep">Yield Trend</h4>
        <div className="flex gap-1">
          {ranges.map((r) => (
            <button
              key={r}
              onClick={() => setRange(r)}
              className={`rounded-lg px-3 py-1 text-xs font-medium transition-colors ${
                range === r
                  ? 'bg-ocean-water/20 text-ocean-water'
                  : 'text-ocean-ink/60 hover:text-ocean-ink'
              }`}
            >
              {r.toUpperCase()}
            </button>
          ))}
        </div>
      </div>

      {/* Chart */}
      <ResponsiveContainer width="100%" height={280}>
        <ComposedChart data={chartData} margin={{ top: 5, right: 10, left: 0, bottom: 5 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="#e2e8f0" />
          <XAxis dataKey="date" tick={{ fontSize: 11, fill: '#64748b' }} />
          <YAxis
            yAxisId="left"
            tick={{ fontSize: 11, fill: '#64748b' }}
            label={{ value: 'Yield', angle: -90, position: 'insideLeft', fontSize: 11, fill: '#64748b' }}
          />
          <YAxis
            yAxisId="right"
            orientation="right"
            tick={{ fontSize: 11, fill: '#64748b' }}
            label={{ value: 'APY %', angle: 90, position: 'insideRight', fontSize: 11, fill: '#64748b' }}
          />
          <Tooltip
            contentStyle={{
              borderRadius: '12px',
              border: '1px solid #e2e8f0',
              fontSize: '12px',
            }}
          />
          <Legend wrapperStyle={{ fontSize: '12px' }} />
          <Area
            yAxisId="left"
            type="monotone"
            dataKey="cumulativeYield"
            name="Cumulative Yield"
            fill="#3b82f6"
            fillOpacity={0.15}
            stroke="#3b82f6"
            strokeWidth={2}
          />
          <Line
            yAxisId="right"
            type="monotone"
            dataKey="apy"
            name="APY %"
            stroke="#10b981"
            strokeWidth={2}
            dot={false}
          />
        </ComposedChart>
      </ResponsiveContainer>
    </div>
  )
}
