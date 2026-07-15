# Mecardee Car Wash — Supabase Launch Tracker

A simple Next.js dashboard that tracks construction phases, task deadlines and opening progress for Mecardee Car Wash.

## What is connected

- Project name, location and target opening date are saved in Supabase.
- Tasks, owners, deadlines, notes and progress are saved in Supabase.
- Changes appear on every phone or computer using the site.
- Supabase Realtime refreshes the dashboard when another device changes the data.
- The bell shows overdue tasks, tasks due today and tasks due within three days.

## One-time database setup

The frontend is already configured with the supplied Supabase project URL and publishable key. The PostgreSQL password is intentionally not included in browser code.

### Easiest method

1. Open the Supabase project dashboard.
2. Open **SQL Editor**.
3. Open `supabase/setup.sql` from this project.
4. Copy all of it into the SQL Editor.
5. Click **Run** once.

The SQL creates the project table, task table, sample tasks, RLS policies and Realtime publication entries.

### CLI method

```bash
supabase login
supabase link --project-ref mvkviijzpxoncruanwce
supabase db push
```

The project is already initialized in this ZIP. Enter the database password only when the Supabase CLI requests it. Do not place it in frontend files or GitHub.

## Run locally

```bash
npm install
npm run dev
```

Open `http://localhost:3000`.

## Deploy to Vercel

1. Push this project to GitHub.
2. In Vercel choose **Add New → Project**.
3. Import the repository.
4. Keep the detected framework as **Next.js**.
5. Click **Deploy**.

The code contains client-safe fallback values for the project URL and publishable key, so Vercel environment variables are optional. For cleaner configuration, you may add:

```text
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
```

## Security note

This simple version has no login. Its RLS policies allow visitors who can open the website to edit the tracker. Keep the Vercel link private. Add Supabase Auth later if access control is needed.
