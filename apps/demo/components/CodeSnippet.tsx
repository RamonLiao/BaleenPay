'use client'

import { useState } from 'react'

interface CodeSnippetProps {
  title: string
  description: string
  code: string
  language?: string
}

export function CodeSnippet({ title, description, code, language = 'TypeScript' }: CodeSnippetProps) {
  const [copied, setCopied] = useState(false)

  const handleCopy = async () => {
    await navigator.clipboard.writeText(code)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <div className="rounded-2xl border border-ocean-foam/20 bg-white overflow-hidden">
      <div className="flex items-center justify-between px-6 py-4 border-b border-ocean-foam/20">
        <div>
          <h3 className="text-lg font-semibold text-ocean-deep">{title}</h3>
          <p className="text-sm text-ocean-ink mt-0.5">{description}</p>
        </div>
        <div className="flex items-center gap-3">
          <span className="rounded-full bg-ocean-mist px-3 py-0.5 text-xs font-medium text-ocean-water">
            {language}
          </span>
          <button
            onClick={handleCopy}
            className="rounded-lg border border-ocean-foam/30 px-3 py-1.5 text-xs font-medium text-ocean-ink hover:bg-ocean-mist transition-colors"
          >
            {copied ? 'Copied!' : 'Copy'}
          </button>
        </div>
      </div>
      <div className="bg-ocean-deep p-6 overflow-auto">
        <pre className="text-sm text-ocean-sky font-mono leading-relaxed whitespace-pre">{code}</pre>
      </div>
    </div>
  )
}
