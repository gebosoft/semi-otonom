import { useEffect, useState } from "react";
import type { HealthResponse } from "@semi-otonom/api-client";

export default function App() {
  const [health, setHealth] = useState<HealthResponse | null>(null);

  useEffect(() => {
    fetch("http://localhost:5027/health")
      .then((r) => r.json())
      .then(setHealth);
  }, []);

  return <div>API: {health?.status ?? "..."}</div>;
}