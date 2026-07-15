import { createClient } from "@supabase/supabase-js";

// These are client-safe Supabase credentials. The publishable key is designed
// to be used in browser applications. Database security is enforced by RLS.
const supabaseUrl =
  process.env.NEXT_PUBLIC_SUPABASE_URL ||
  "https://mvkviijzpxoncruanwce.supabase.co";

const supabasePublishableKey =
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ||
  "sb_publishable_2CsVAl---Eae53ls-J8TzA_xA--dYfr";

export const supabase = createClient(supabaseUrl, supabasePublishableKey, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
    detectSessionInUrl: false
  }
});
