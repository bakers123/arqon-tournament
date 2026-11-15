-- This SECURITY DEFINER function is a table trigger only, not an RPC endpoint.
-- Trigger execution remains intact after revoking direct caller privileges.
revoke all on function public.prepare_live_match_chat_message() from public;
revoke all on function public.prepare_live_match_chat_message() from anon;
revoke all on function public.prepare_live_match_chat_message() from authenticated;
