import { useEffect, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { request } from '../../api/client';

export function useRoomSync(cid: string, enabled: boolean) {
  const qc = useQueryClient();
  const [status, setStatus] = useState<'connecting'|'live'|'reconnecting'>('connecting');
  useEffect(() => {
    if (!cid || !enabled) return;
    let revoked = false;
    let last: number | null = null;
    let source: EventSource | undefined;
    let fallback: ReturnType<typeof setInterval> | undefined;
    let pending: AbortController | undefined;
    const inCampaign = (key: string) => new URL(key, 'http://sessionlab.invalid').searchParams.get('campaign') === cid;
    const invalidate = () => {
      qc.invalidateQueries({ predicate: q => {
        const key = String(q.queryKey[0]);
        return key === 'campaigns' || inCampaign(key) || key === `/campaigns/${cid}/sessions/`;
      }});
    };
    const accept = (n: number) => {
      if (!Number.isInteger(n) || last === n) return;
      last = n;
      invalidate();
    };
    const poll = async () => {
      if (pending || document.hidden || revoked) return;
      const controller = new AbortController();
      pending = controller;
      try {
        const state = await request(`/room/?campaign=${cid}`, 'GET', undefined, controller.signal);
        if (!controller.signal.aborted) accept(state.revision);
      } catch { /* Existing error states remain visible; EventSource reconnects. */ }
      finally { if (pending === controller) pending = undefined; }
    };
    const startFallback = () => {
      if (fallback === undefined) fallback = setInterval(poll, 5000);
    };
    const stopFallback = () => {
      if (fallback !== undefined) clearInterval(fallback);
      fallback = undefined;
      pending?.abort();
      pending = undefined;
    };
    const stop = () => {
      const stream = source;
      source = undefined;
      stream?.close();
      stopFallback();
    };
    const start = () => {
      if (revoked || document.hidden || source || fallback !== undefined) return;
      setStatus('connecting');
      if (typeof EventSource === 'undefined') {
        setStatus('reconnecting');
        startFallback();
        return;
      }
      const stream = new EventSource(`/api/campaigns/${cid}/stream/`, { withCredentials: true });
      source = stream;
      stream.onopen = () => {
        if (source !== stream) return;
        setStatus('live');
        stopFallback();
      };
      stream.addEventListener('change', e => {
        if (source !== stream) return;
        try { accept(JSON.parse((e as MessageEvent).data).revision); } catch { /* malformed event */ }
      });
      stream.addEventListener('revoked', () => {
        if (source !== stream) return;
        revoked = true;
        stop();
        setStatus('reconnecting');
        qc.removeQueries({ predicate: q => inCampaign(String(q.queryKey[0])) || String(q.queryKey[0]) === `/campaigns/${cid}/sessions/` });
        qc.invalidateQueries({ queryKey: ['campaigns'] });
        qc.invalidateQueries({ queryKey: ['me'] });
      });
      stream.onerror = () => {
        if (source !== stream) return;
        setStatus('reconnecting');
        startFallback();
      };
    };
    const onVisibility = () => {
      if (document.hidden) {
        stop();
      } else if (!revoked) {
        invalidate();
        start();
      }
    };
    const onFocus = () => { if (!document.hidden && !revoked) invalidate(); };
    start();
    document.addEventListener('visibilitychange', onVisibility);
    window.addEventListener('focus', onFocus);
    return () => {
      stop();
      document.removeEventListener('visibilitychange', onVisibility);
      window.removeEventListener('focus', onFocus);
    };
  }, [cid, enabled, qc]);
  return status;
}
