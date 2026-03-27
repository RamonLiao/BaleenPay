// packages/sdk/src/events/queries.ts

/**
 * GraphQL query for paginated event listing.
 * Used by EventStream (polling) and getPaymentHistory.
 */
export const QUERY_EVENTS = `
  query QueryEvents(
    $type: String!
    $after: String
    $first: Int
  ) {
    events(
      filter: { type: $type }
      after: $after
      first: $first
    ) {
      nodes {
        contents { json }
        sender { address }
        type { repr }
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
`

/** Response type for QUERY_EVENTS */
export interface QueryEventsResult {
  events: {
    nodes: Array<{
      contents: { json: Record<string, unknown> } | null
      sender: { address: string } | null
      type: { repr: string } | null
    }>
    pageInfo: {
      hasNextPage: boolean
      endCursor: string | null
    }
  }
}
