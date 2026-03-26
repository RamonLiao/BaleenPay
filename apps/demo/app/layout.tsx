import { ClientShell } from '@/components/ClientShell'
import './globals.css'

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="bg-ocean-surface text-ocean-deep font-sans antialiased">
        <ClientShell>
          {children}
        </ClientShell>
      </body>
    </html>
  )
}
