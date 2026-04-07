import { CodeSnippet } from '@/components/CodeSnippet'
import { DEVELOPER_SNIPPETS } from '@/lib/snippets'

export default function DevelopersPage() {
  return (
    <div className="mx-auto max-w-3xl px-6 py-16">
      <p className="text-xs font-semibold uppercase tracking-[1.5px] text-ocean-sui mb-3">
        Developer Guide
      </p>
      <h1 className="text-3xl font-bold text-ocean-deep mb-4">
        Integrate BaleenPay in minutes
      </h1>
      <p className="text-ocean-ink mb-12 max-w-xl">
        TypeScript SDK with React hooks and drop-in components.
        Same patterns you know from Stripe — built for SUI.
      </p>

      <div className="space-y-8">
        {DEVELOPER_SNIPPETS.map((snippet) => (
          <CodeSnippet
            key={snippet.title}
            title={snippet.title}
            description={snippet.description}
            code={snippet.code}
          />
        ))}
      </div>
    </div>
  )
}
