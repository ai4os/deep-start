import { Plugin } from "@opencode/plugin"

/**
 * AI4EOSC web search provider for OpenCode (SearXNG backend behind the
 * AI4EOSC vLLM gateway).
 *
 * Registers a custom websearch provider into the pool that OpenCode's
 * websearch tool selects from (including `"websearch": { "provider": "random" }`).
 *
 * Configuration (environment variables, provided by the platform):
 * - AI4EOSC_LLM_KEY   - bearer token for the search endpoint (required;
 *                       the plugin registers nothing while it is unset)
 * - AI4EOSC_SEARCH_URL - optional endpoint override, defaults to
 *                       https://vllm.cloud.ai4eosc.eu/v1/search/searxng-search
 *
 * Endpoint request:  POST {query, max_results, search_domain_filter?, country?}
 * Endpoint response: { results: [{ title, url, snippet, date, last_updated }], object }
 */
const DEFAULT_SEARCH_URL = "https://vllm.cloud.ai4eosc.eu/v1/search/searxng-search"

export default Plugin.define({
  id: "ai4eosc.search",
  async setup(ctx) {
    const key = process.env.AI4EOSC_LLM_KEY
    if (!key) {
      console.log(
        "[ai4eosc-search] AI4EOSC_LLM_KEY is not set, search provider not registered",
      )
      return
    }
    const url = process.env.AI4EOSC_SEARCH_URL ?? DEFAULT_SEARCH_URL

    await ctx.websearch.transform((editor) => {
      editor.add({
        id: "ai4eosc",
        name: "AI4EOSC Search",
        execute: async ({ query }, { signal }) => {
          const response = await fetch(url, {
            method: "POST",
            headers: {
              Authorization: `Bearer ${key}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({ query, max_results: 8 }),
            signal,
          })
          if (!response.ok) {
            throw new Error(`AI4EOSC search failed: HTTP ${response.status}`)
          }

          const data = await response.json()
          const results = Array.isArray(data?.results) ? data.results : []
          return results.map((r: any) => ({
            url: r.url,
            title: r.title,
            content: r.content ?? r.snippet ?? "",
            // result also carries `date` and `last_updated` if ever needed
            time: {},
          }))
        },
      })
    })
  },
})
