import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { act, cleanup, renderHook } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';
import { useRoomSync } from './useRoomSync';
import { request } from '../../api/client';

vi.mock('../../api/client', () => ({ request: vi.fn() }));
class Stream {
  static current: Stream;
  onopen?: () => void;
  onerror?: () => void;
  closed = false;
  listeners = new Map<string, (event: {data: string}) => void>();
  constructor(public url: string) { Stream.current = this; }
  addEventListener(name: string, fn: (event: {data: string}) => void) { this.listeners.set(name, fn); }
  emit(name: string, data: unknown) { this.listeners.get(name)?.({data: JSON.stringify(data)}); }
  close() { this.closed = true; }
}
beforeEach(() => { vi.stubGlobal('EventSource', Stream); });
afterEach(() => { cleanup(); vi.useRealTimers(); vi.unstubAllGlobals(); vi.clearAllMocks(); });
function mount() {
  const qc = new QueryClient({defaultOptions: {queries: {retry: false, gcTime: Infinity}}});
  qc.setQueryData(['/room/?campaign=1'], {revision: 1});
  qc.setQueryData(['/room/?campaign=10'], {revision: 3});
  qc.setQueryData(['campaigns'], []);
  qc.setQueryData(['me'], {});
  const wrapper = ({children}: {children: ReactNode}) => <QueryClientProvider client={qc}>{children}</QueryClientProvider>;
  return {qc, ...renderHook(() => useRoomSync('1', true), {wrapper})};
}
it('invalidates only the changed campaign and ignores duplicate revision events', () => {
  const {qc, result, unmount} = mount();
  expect(Stream.current.url).toBe('/api/campaigns/1/stream/');
  act(() => { Stream.current.onopen?.(); Stream.current.emit('change', {revision: 2}); });
  expect(result.current).toBe('live');
  expect(qc.getQueryState(['/room/?campaign=1'])?.isInvalidated).toBe(true);
  expect(qc.getQueryState(['/room/?campaign=10'])?.isInvalidated).toBe(false);
  qc.setQueryData(['/room/?campaign=1'], {revision: 2});
  act(() => Stream.current.emit('change', {revision: 2}));
  expect(qc.getQueryState(['/room/?campaign=1'])?.isInvalidated).toBe(false);
  unmount(); expect(Stream.current.closed).toBe(true);
});
it('removes revoked campaign data while preserving another campaign', () => {
  const {qc} = mount();
  act(() => Stream.current.emit('revoked', {}));
  expect(Stream.current.closed).toBe(true);
  expect(qc.getQueryData(['/room/?campaign=1'])).toBeUndefined();
  expect(qc.getQueryData(['/room/?campaign=10'])).toBeDefined();
  expect(qc.getQueryState(['me'])?.isInvalidated).toBe(true);
});
it('polls while disconnected and stops polling when the stream recovers', async () => {
  vi.useFakeTimers();
  vi.mocked(request).mockResolvedValue({revision: 4});
  const {qc, result} = mount();
  act(() => Stream.current.onerror?.());
  expect(result.current).toBe('reconnecting');
  await act(async () => { await vi.advanceTimersByTimeAsync(5000); });
  expect(request).toHaveBeenCalledWith('/room/?campaign=1');
  expect(qc.getQueryState(['/room/?campaign=1'])?.isInvalidated).toBe(true);
  act(() => Stream.current.onopen?.());
  await act(async () => { await vi.advanceTimersByTimeAsync(10000); });
  expect(request).toHaveBeenCalledTimes(1);
});
