import { useEffect, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { request } from '../../api/client';

export function useRoomSync(cid: string, enabled: boolean) {
  const qc = useQueryClient();
  const [status, setStatus] = useState<'connecting'|'live'|'reconnecting'>('connecting');
  useEffect(() => {
    if (!cid || !enabled) return;
    let disposed = false, last: number | null = null, fallback: ReturnType<typeof setInterval> | undefined;
    let source: EventSource | undefined;
    const inCampaign = (key: string) => new URL(key, 'http://sessionlab.invalid').searchParams.get('campaign') === cid;
    const invalidate = () => {
      qc.invalidateQueries({ predicate: q => {
        const key = String(q.queryKey[0]);
        return key === 'campaigns' || inCampaign(key) || key === `/campaigns/${cid}/sessions/`;
      }});
    };
    const accept = (n: number) => {
      if (disposed || !Number.isInteger(n)) return;
      if (last !== n) { last = n; invalidate(); }
    };
    const poll = async () => {
      try {
        const state = await request(`/room/?campaign=${cid}`);
        accept(state.revision);
      } catch { /* Existing error states remain visible; EventSource reconnects. */ }
    };
    const startFallback = () => { if (!fallback) fallback = setInterval(poll, 5000); };
    setStatus('connecting');
    if (typeof EventSource !== 'undefined') {
      source = new EventSource(`/api/campaigns/${cid}/stream/`, { withCredentials: true });
      source.onopen = () => { setStatus('live'); if (fallback) { clearInterval(fallback); fallback = undefined; } };
      source.addEventListener('change', e => {
        try { accept(JSON.parse((e as MessageEvent).data).revision); } catch { /* malformed event */ }
      });
      source.addEventListener('revoked', () => {
        source?.close(); setStatus('reconnecting');
        if (fallback) { clearInterval(fallback); fallback = undefined; }
        qc.removeQueries({ predicate: q => inCampaign(String(q.queryKey[0])) || String(q.queryKey[0]) === `/campaigns/${cid}/sessions/` });
        qc.invalidateQueries({ queryKey: ['campaigns'] });
        qc.invalidateQueries({ queryKey: ['me'] });
      });
      source.onerror = () => { if (!disposed) { setStatus('reconnecting'); startFallback(); } };
    } else { setStatus('reconnecting'); startFallback(); }
    const onFocus = () => invalidate();
    window.addEventListener('focus', onFocus);
    return () => { disposed = true; source?.close(); if (fallback) clearInterval(fallback); window.removeEventListener('focus', onFocus); };
  }, [cid, enabled, qc]);
  return status;
}
