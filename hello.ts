Bun.serve({ port: Number(process.env.PORT), fetch: () => new Response("hi") });
