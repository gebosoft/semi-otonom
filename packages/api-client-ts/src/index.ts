import type { paths, components } from "./schema";

export type { paths, components };

export type Schemas = components["schemas"];

export type HealthResponse =
  paths["/health"]["get"]["responses"]["200"]["content"]["application/json"];