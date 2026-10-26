import React from "react";
import ReactDOM from "react-dom/client";
import { BrowserRouter } from "react-router-dom";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import App from "./app";
import "./styles.css";
document.documentElement.dataset.theme = localStorage.getItem("sl:theme") === "dark" ? "dark" : "light";
const client = new QueryClient({
  defaultOptions: {
    queries: { staleTime: 20000, refetchOnWindowFocus: true, retry: 1 },
    mutations: { retry: false },
  },
});
ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <QueryClientProvider client={client}>
      <BrowserRouter>
        <App />
      </BrowserRouter>
    </QueryClientProvider>
  </React.StrictMode>,
);

import "./features/sheets/sheets.css";
import "./features/sheets/classic.css";
