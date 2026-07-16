"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { supabase } from "../lib/supabase";
import pdfMake from "pdfmake/build/pdfmake";
import pdfFonts from "pdfmake/build/vfs_fonts";
pdfMake.vfs = pdfFonts; // Roboto font included

const PHASES = [
  { id: "site", name: "Site & Civil", short: "Civil", icon: "▦" },
  { id: "water", name: "Water & Drainage", short: "Water", icon: "≈" },
  { id: "electrical", name: "Electrical & Safety", short: "Electric", icon: "ϟ" },
  { id: "equipment", name: "Equipment Installation", short: "Equipment", icon: "⚙" },
  { id: "brand", name: "Branding & Customer Area", short: "Branding", icon: "✦" },
  { id: "launch", name: "Staff & Launch", short: "Launch", icon: "✓" }
];

const pad = (value) => String(value).padStart(2, "0");
// MECARDEE_SIMPLE_USERS_V1
const USER_SESSION_KEY = "mecardee-user-session";
const EMPTY_PHASE_BUDGETS = Object.fromEntries(PHASES.map((phase) => [phase.id, 0]));
// MECARDEE_BUDGET_LOGIN_PATCH

function formatMoney(value) {
  return new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    maximumFractionDigits: 0
  }).format(Number(value || 0));
}

function toDateInput(date) {
  const d = new Date(date);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function dateFromNow(days) {
  const date = new Date();
  date.setHours(12, 0, 0, 0);
  date.setDate(date.getDate() + days);
  return toDateInput(date);
}

function createInitialData() {
  return {
    project: {
      name: "Mecardee Car Wash",
      location: "Kerala, India",
      openingDate: dateFromNow(100),
      totalBudget: 0,
      phaseBudgets: { ...EMPTY_PHASE_BUDGETS }
    },
    tasks: [
      { id: crypto.randomUUID(), title: "Complete site clearing and measurements", phase: "site", owner: "Civil contractor", deadline: dateFromNow(5), progress: 70, notes: "Confirm entry and exit vehicle turning space." },
      { id: crypto.randomUUID(), title: "Finish wash-bay flooring and slope", phase: "site", owner: "Civil contractor", deadline: dateFromNow(18), progress: 25, notes: "Use anti-skid flooring and verify drainage slope." },
      { id: crypto.randomUUID(), title: "Install drainage channels", phase: "water", owner: "Plumber", deadline: dateFromNow(24), progress: 10, notes: "Include sludge trap and easy cleaning access." },
      { id: crypto.randomUUID(), title: "Install water tank, pump and pipelines", phase: "water", owner: "Plumber", deadline: dateFromNow(32), progress: 0, notes: "Keep provision for recycling system." },
      { id: crypto.randomUUID(), title: "Complete three-phase wiring and lights", phase: "electrical", owner: "Electrician", deadline: dateFromNow(40), progress: 0, notes: "Separate protected points for pressure washers." },
      { id: crypto.randomUUID(), title: "Install CCTV and fire extinguishers", phase: "electrical", owner: "Electrician", deadline: dateFromNow(48), progress: 0, notes: "Cover wash bay, office, entrance and exit." },
      { id: crypto.randomUUID(), title: "Install pressure washer and compressor", phase: "equipment", owner: "Equipment supplier", deadline: dateFromNow(58), progress: 0, notes: "Test pressure, leakage and warranty documents." },
      { id: crypto.randomUUID(), title: "Set up vacuum and detailing tools", phase: "equipment", owner: "Equipment supplier", deadline: dateFromNow(64), progress: 0, notes: "Prepare locked storage for chemicals and tools." },
      { id: crypto.randomUUID(), title: "Complete signboard and price menu", phase: "brand", owner: "Designer", deadline: dateFromNow(72), progress: 0, notes: "Use Malayalam and English where useful." },
      { id: crypto.randomUUID(), title: "Finish customer waiting and billing area", phase: "brand", owner: "Interior team", deadline: dateFromNow(78), progress: 0, notes: "Add seating, drinking water and UPI QR display." },
      { id: crypto.randomUUID(), title: "Recruit and train wash staff", phase: "launch", owner: "Owner", deadline: dateFromNow(86), progress: 0, notes: "Train on wash sequence, safety and customer handling." },
      { id: crypto.randomUUID(), title: "Trial wash and soft opening", phase: "launch", owner: "Owner", deadline: dateFromNow(95), progress: 0, notes: "Test billing, workflow, water use and turnaround time." }
    ]
  };
}


function mapProject(row) {
  return {
    name: row.name,
    location: row.location,
    openingDate: row.opening_date,
    totalBudget: Number(row.total_budget || 0),
    phaseBudgets: {
      ...EMPTY_PHASE_BUDGETS,
      ...(row.phase_budgets || {})
    }
  };
}

function mapTask(row) {
  return {
    id: row.id,
    title: row.title,
    phase: row.phase,
    owner: row.owner || "",
    deadline: row.deadline,
    progress: Number(row.progress || 0),
    expectedCost: Number(row.expected_cost || 0),
    actualCost: Number(row.actual_cost || 0),
    notes: row.notes || "",
    sortOrder: Number(row.sort_order || 0)
  };
}

function taskPatchForDatabase(patch) {
  const databasePatch = {};
  if (Object.hasOwn(patch, "title")) databasePatch.title = patch.title;
  if (Object.hasOwn(patch, "phase")) databasePatch.phase = patch.phase;
  if (Object.hasOwn(patch, "owner")) databasePatch.owner = patch.owner;
  if (Object.hasOwn(patch, "deadline")) databasePatch.deadline = patch.deadline;
  if (Object.hasOwn(patch, "progress")) databasePatch.progress = Number(patch.progress);
  if (Object.hasOwn(patch, "expectedCost")) databasePatch.expected_cost = Number(patch.expectedCost || 0);
  if (Object.hasOwn(patch, "actualCost")) databasePatch.actual_cost = Number(patch.actualCost || 0);
  if (Object.hasOwn(patch, "notes")) databasePatch.notes = patch.notes;
  if (Object.hasOwn(patch, "sortOrder")) databasePatch.sort_order = Number(patch.sortOrder);
  return databasePatch;
}

async function fetchTrackerData() {
  const [projectResult, tasksResult] = await Promise.all([
    supabase.from("mecardee_project").select("*").eq("id", 1).maybeSingle(),
    supabase.from("mecardee_tasks").select("*").order("sort_order", { ascending: true }).order("deadline", { ascending: true })
  ]);

  if (projectResult.error) throw projectResult.error;
  if (tasksResult.error) throw tasksResult.error;

  let projectRow = projectResult.data;
  if (!projectRow) {
    const sample = createInitialData().project;
    const created = await supabase
      .from("mecardee_project")
      .upsert({
        id: 1,
        name: sample.name,
        location: sample.location,
        opening_date: sample.openingDate,
        total_budget: sample.totalBudget,
        phase_budgets: sample.phaseBudgets
      })
      .select("*")
      .single();

    if (created.error) throw created.error;
    projectRow = created.data;
  }

  return {
    project: mapProject(projectRow),
    tasks: (tasksResult.data || []).map(mapTask)
  };
}

function parseLocalDate(value) {
  if (!value) return null;
  return new Date(`${value}T12:00:00`);
}

function startOfToday() {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d;
}

function daysBetween(from, to) {
  const oneDay = 1000 * 60 * 60 * 24;
  return Math.ceil((to.getTime() - from.getTime()) / oneDay);
}

function formatDate(value, options = { day: "numeric", month: "short", year: "numeric" }) {
  const date = parseLocalDate(value);
  if (!date) return "No date";
  return new Intl.DateTimeFormat("en-IN", options).format(date);
}

function statusFor(task) {
  if (Number(task.progress) >= 100) return "Completed";
  const deadline = parseLocalDate(task.deadline);
  if (deadline && deadline < startOfToday()) return "Overdue";
  if (Number(task.progress) > 0) return "In progress";
  return "Not started";
}

function taskAlert(task) {
  if (Number(task.progress) >= 100) return null;
  const deadline = parseLocalDate(task.deadline);
  if (!deadline) return null;
  const days = daysBetween(startOfToday(), deadline);
  if (days < 0) {
    const late = Math.abs(days);
    return {
      level: "danger",
      title: `${task.title} is overdue`,
      detail: `${late} day${late === 1 ? "" : "s"} late · ${task.owner || "No owner"}`
    };
  }
  if (days === 0) {
    return { level: "danger", title: `${task.title} is due today`, detail: task.owner || "No owner" };
  }
  if (days <= 3) {
    return { level: "warning", title: `${task.title} is due soon`, detail: `${days} day${days === 1 ? "" : "s"} remaining · ${task.owner || "No owner"}` };
  }
  return null;
}

function ProgressRing({ value, size = 158 }) {
  const stroke = 12;
  const radius = (size - stroke) / 2;
  const circumference = radius * 2 * Math.PI;
  const offset = circumference - (Math.min(100, Math.max(0, value)) / 100) * circumference;

  return (
    <div className="ring-wrap" style={{ width: size, height: size }}>
      <svg className="progress-ring" width={size} height={size} viewBox={`0 0 ${size} ${size}`}>
        <circle className="ring-track" strokeWidth={stroke} fill="transparent" r={radius} cx={size / 2} cy={size / 2} />
        <circle
          className="ring-value"
          strokeWidth={stroke}
          strokeLinecap="round"
          fill="transparent"
          r={radius}
          cx={size / 2}
          cy={size / 2}
          strokeDasharray={`${circumference} ${circumference}`}
          strokeDashoffset={offset}
        />
      </svg>
      <div className="ring-label">
        <strong>{value}%</strong>
        <span>complete</span>
      </div>
    </div>
  );
}

function Modal({ title, children, onClose }) {
  useEffect(() => {
    const close = (event) => event.key === "Escape" && onClose();
    window.addEventListener("keydown", close);
    return () => window.removeEventListener("keydown", close);
  }, [onClose]);

  return (
    <div className="modal-backdrop" onMouseDown={(event) => event.target === event.currentTarget && onClose()}>
      <section className="modal-card" role="dialog" aria-modal="true" aria-label={title}>
        <div className="modal-head">
          <div>
            <span className="eyebrow">Mecardee tracker</span>
            <h2>{title}</h2>
          </div>
          <button className="icon-button" onClick={onClose} aria-label="Close">×</button>
        </div>
        {children}
      </section>
    </div>
  );
}

export default function Home() {
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const [currentUser, setCurrentUser] = useState(null);
  const [authChecked, setAuthChecked] = useState(false);
  const [loginError, setLoginError] = useState("");
  const [accountBusy, setAccountBusy] = useState(false);
  const [accountMessage, setAccountMessage] = useState("");
  const [data, setData] = useState(null);
  const [activePhase, setActivePhase] = useState("all");
  const [showTaskModal, setShowTaskModal] = useState(false);
  const [showSettings, setShowSettings] = useState(false);
  const [showAccountSettings, setShowAccountSettings] = useState(false);
  const [showAlerts, setShowAlerts] = useState(false);
  const [activeSummary, setActiveSummary] = useState(null);
  const [taskDrafts, setTaskDrafts] = useState({});
  const [toast, setToast] = useState("");
  const [isSyncing, setIsSyncing] = useState(false);
  const [loadError, setLoadError] = useState("");
  const [isExporting, setIsExporting] = useState(false);
  const [newTask, setNewTask] = useState({
    title: "",
    phase: "site",
    owner: "",
    deadline: dateFromNow(7),
    progress: 0,
    expectedCost: 0,
    notes: ""
  });

  useEffect(() => {
    let cancelled = false;

    async function restoreUserSession() {
      try {
        const rawSession = window.sessionStorage.getItem(USER_SESSION_KEY);
        if (!rawSession) return;

        const savedSession = JSON.parse(rawSession);
        if (!savedSession?.token) return;

        const { data: result, error } = await supabase.rpc("mecardee_session_info", {
          p_session_token: savedSession.token
        });

        const sessionUser = Array.isArray(result) ? result[0] : result;
        if (error || !sessionUser) {
          window.sessionStorage.removeItem(USER_SESSION_KEY);
          return;
        }

        if (!cancelled) {
          const restoredUser = {
            token: savedSession.token,
            username: sessionUser.username,
            isAdmin: Boolean(sessionUser.is_admin)
          };
          setCurrentUser(restoredUser);
          setIsLoggedIn(true);
        }
      } catch {
        window.sessionStorage.removeItem(USER_SESSION_KEY);
      } finally {
        if (!cancelled) setAuthChecked(true);
      }
    }

    restoreUserSession();
    return () => {
      cancelled = true;
    };
  }, []);

  const loadData = useCallback(async ({ quiet = false } = {}) => {
    if (!quiet) setIsSyncing(true);
    try {
      const nextData = await fetchTrackerData();
      setData(nextData);
      setLoadError("");
    } catch (error) {
      console.error("Mecardee database load failed:", error);
      setLoadError(
        error?.code === "42P01" || error?.code === "PGRST205" || String(error?.message || "").includes("schema cache")
          ? "Database tables are not ready. Run supabase/setup.sql once in the Supabase SQL Editor, then retry."
          : error?.message || "Could not connect to the Mecardee database."
      );
    } finally {
      if (!quiet) setIsSyncing(false);
    }
  }, []);

  useEffect(() => {
    if (!isLoggedIn) return;
    loadData();

    const channel = supabase
      .channel("mecardee-live-tracker")
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "mecardee_project" },
        () => loadData({ quiet: true })
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "mecardee_tasks" },
        () => loadData({ quiet: true })
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [loadData, isLoggedIn]);

  const phaseStats = useMemo(() => {
    if (!data) return {};
    return Object.fromEntries(
      PHASES.map((phase) => {
        const tasks = data.tasks.filter((task) => task.phase === phase.id);
        const average = tasks.length
          ? Math.round(tasks.reduce((sum, task) => sum + Number(task.progress || 0), 0) / tasks.length)
          : 0;
        const deadlines = tasks.map((task) => parseLocalDate(task.deadline)).filter(Boolean);
        const target = deadlines.length ? new Date(Math.max(...deadlines.map((date) => date.getTime()))) : null;
        const expected = tasks.reduce((sum, task) => sum + Number(task.expectedCost || 0), 0);
        const spent = tasks.reduce((sum, task) => sum + Number(task.actualCost || 0), 0);
        const budget = Number(data.project.phaseBudgets?.[phase.id] || 0);
        return [phase.id, {
          progress: average,
          count: tasks.length,
          target,
          expected,
          spent,
          budget,
          available: budget - spent
        }];
      })
    );
  }, [data]);

  const overallProgress = useMemo(() => {
    if (!data?.tasks.length) return 0;
    return Math.round(data.tasks.reduce((sum, task) => sum + Number(task.progress || 0), 0) / data.tasks.length);
  }, [data]);

  const alerts = useMemo(() => {
    if (!data) return [];
    const taskAlerts = data.tasks.map(taskAlert).filter(Boolean);
    const openingDate = parseLocalDate(data.project.openingDate);
    if (openingDate) {
      const days = daysBetween(startOfToday(), openingDate);
      if (days < 0) {
        taskAlerts.unshift({ level: "danger", title: "Opening date has passed", detail: "Update the project opening date in Settings." });
      } else if (days <= 14) {
        taskAlerts.unshift({ level: "warning", title: "Opening day is getting close", detail: `${days} day${days === 1 ? "" : "s"} remaining` });
      }
    }
    return taskAlerts;
  }, [data]);

  const openingDays = useMemo(() => {
    if (!data) return 0;
    const opening = parseLocalDate(data.project.openingDate);
    return opening ? Math.max(0, daysBetween(startOfToday(), opening)) : 0;
  }, [data]);

  const completedTasks = data?.tasks.filter((task) => Number(task.progress) >= 100).length || 0;
  const overdueTasks = data?.tasks.filter((task) => statusFor(task) === "Overdue").length || 0;
  const totalExpected = data?.tasks.reduce((sum, task) => sum + Number(task.expectedCost || 0), 0) || 0;
  const totalSpent = data?.tasks.reduce((sum, task) => sum + Number(task.actualCost || 0), 0) || 0;
  const totalBudget = Number(data?.project.totalBudget || 0);
  const totalAvailable = totalBudget - totalSpent;
  const taskCompletionPercent = data?.tasks?.length ? Math.round((completedTasks / data.tasks.length) * 100) : 0;
  const activePhaseCount = PHASES.filter((phase) => phaseStats[phase.id]?.progress > 0 && phaseStats[phase.id]?.progress < 100).length;
  const overdueTaskList = data?.tasks?.filter((task) => statusFor(task) === "Overdue") || [];
  const completedTaskList = data?.tasks?.filter((task) => Number(task.progress) >= 100) || [];
  const activePhaseList = PHASES.filter((phase) => phaseStats[phase.id]?.progress > 0 && phaseStats[phase.id]?.progress < 100);


  async function handleLogin(event) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const username = String(form.get("username") || "").trim().toLowerCase();
    const password = String(form.get("password") || "");

    setAccountBusy(true);
    setLoginError("");

    const { data: result, error } = await supabase.rpc("mecardee_login", {
      p_username: username,
      p_password: password
    });

    setAccountBusy(false);
    const session = Array.isArray(result) ? result[0] : result;

    if (error || !session?.session_token) {
      setLoginError("Incorrect username or password.");
      return;
    }

    const user = {
      token: session.session_token,
      username: session.username,
      isAdmin: Boolean(session.is_admin)
    };

    window.sessionStorage.setItem(USER_SESSION_KEY, JSON.stringify(user));
    setCurrentUser(user);
    setLoginError("");
    setIsLoggedIn(true);
  }

  async function logout() {
    const token = currentUser?.token;
    window.sessionStorage.removeItem(USER_SESSION_KEY);
    setData(null);
    setShowAlerts(false);
    setShowAccountSettings(false);
    setCurrentUser(null);
    setIsLoggedIn(false);

    if (token) {
      await supabase.rpc("mecardee_logout", {
        p_session_token: token
      });
    }
  }

  async function addNewUser(event) {
    event.preventDefault();
    if (!currentUser?.isAdmin) return;

    const form = new FormData(event.currentTarget);
    const username = String(form.get("newUsername") || "").trim().toLowerCase();
    const password = String(form.get("newPassword") || "");
    const confirmPassword = String(form.get("confirmNewPassword") || "");

    if (password !== confirmPassword) {
      setAccountMessage("New-user passwords do not match.");
      return;
    }

    setAccountBusy(true);
    setAccountMessage("");

    const { data: message, error } = await supabase.rpc("mecardee_add_user", {
      p_session_token: currentUser.token,
      p_username: username,
      p_password: password
    });

    setAccountBusy(false);

    if (error) {
      setAccountMessage(error.message || "Could not create the user.");
      return;
    }

    event.currentTarget.reset();
    setAccountMessage(String(message || "User created successfully."));
  }

  async function changeCurrentPassword(event) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const currentPassword = String(form.get("currentPassword") || "");
    const newPassword = String(form.get("changedPassword") || "");
    const confirmPassword = String(form.get("confirmChangedPassword") || "");

    if (newPassword !== confirmPassword) {
      setAccountMessage("New passwords do not match.");
      return;
    }

    setAccountBusy(true);
    setAccountMessage("");

    const { data: message, error } = await supabase.rpc("mecardee_change_password", {
      p_session_token: currentUser.token,
      p_current_password: currentPassword,
      p_new_password: newPassword
    });

    setAccountBusy(false);

    if (error) {
      setAccountMessage(error.message || "Could not change the password.");
      return;
    }

    event.currentTarget.reset();
    setAccountMessage(String(message || "Password changed successfully."));
  }

  function notify(message) {
    setToast(message);
    window.setTimeout(() => setToast(""), 2400);
  }

  async function handleExportReport() {
    if (!data) { notify("No data to export."); return; }
    setIsExporting(true);
    try {
      const overallProgress = Math.round(
        data.tasks.reduce((s, t) => s + Number(t.progress || 0), 0) / (data.tasks.length || 1)
      );
      const completedCount = data.tasks.filter(t => Number(t.progress) >= 100).length;
      const overdueTasks = data.tasks.filter(t => statusFor(t) === "Overdue");
      const nearTasks = data.tasks.filter(t => {
        const d = parseLocalDate(t.deadline);
        if (!d || Number(t.progress) >= 100) return false;
        return daysBetween(startOfToday(), d) >= 0 && daysBetween(startOfToday(), d) <= 3;
      });

      const DARK = "#071a17";
      const LIME = "#d7ff4f";
      const AQUA = "#49d6bd";
      const PAPER = "#f5f7f3";
      const INK = "#10201d";
      const MUTED = "#64736f";
      const LINE = "#dfe6e2";
      const DANGER = "#d6493f";
      const WARN = "#c77a14";

      const safeFmt = (v) => {
        if (!v) return "—";
        const d = parseLocalDate(v);
        if (!d || isNaN(d.getTime())) return "—";
        return new Intl.DateTimeFormat("en-IN", { day: "numeric", month: "short", year: "numeric" }).format(d);
      };
      const fmt = (v, o = { day: "numeric", month: "long", year: "numeric" }) => {
        if (!v) return "—";
        const d = parseLocalDate(v);
        if (!d || isNaN(d.getTime())) return "—";
        return new Intl.DateTimeFormat("en-IN", o).format(d);
      };
      const fmtShort = safeFmt;
      const fmtDate = () => new Intl.DateTimeFormat("en-IN", { day: "numeric", month: "long", year: "numeric" }).format(new Date());
      const openDate = parseLocalDate(data.project.openingDate);
      const daysRem = openDate ? Math.max(0, daysBetween(startOfToday(), openDate)) : null;

      const statusColor = (s) =>
        s === "Completed" ? { text: "#4b8618", bg: "#eff8e5" }
        : s === "Overdue" ? { text: DANGER, bg: "#fff0ee" }
        : s === "In progress" ? { text: "#087666", bg: "#dff8f2" }
        : { text: MUTED, bg: PAPER };

      const makeSectionHead = (label, title) => [
        { text: label, fontSize: 8, color: AQUA, bold: true, letterSpacing: 1.5, margin: [0, 0, 0, 2] },
        { text: title, fontSize: 22, bold: true, color: DARK, margin: [0, 0, 0, 14] },
        {
  canvas: [
    {
      type: "line",
      x1: 0,
      y1: 0,
      x2: 475,
      y2: 0,
      lineWidth: 1.5,
      lineColor: LINE
    }
  ],
  margin: [0, 0, 0, 16]
}
      ];

      const makeKPI = (label, value, note, opts = {}) => {
        const {
          labelColor = MUTED,
          valueColor = INK,
          noteColor = MUTED,
          ...boxOptions
        } = opts;

        return {
          stack: [
            {
              text: label,
              fontSize: 8,
              color: labelColor,
              bold: true,
              margin: [0, 0, 0, 4]
            },
            {
              text: value,
              fontSize: 26,
              bold: true,
              color: valueColor
            },
            note
              ? {
                  text: note,
                  fontSize: 9,
                  color: noteColor,
                  margin: [0, 4, 0, 0]
                }
              : null
          ].filter(Boolean),
          ...boxOptions
        };
      };

      const doc = {
        pageSize: "A4",
        pageMargins: [50, 50, 50, 50],
        content: [
          // ── COVER ──────────────────────────────────────────────────────
          {
            canvas: [{ type: "rect", x: 0, y: 0, w: 595.28, h: 841.89, color: DARK }],
            absolutePosition: { x: 0, y: 0 }
          },
          // brand mark
          {
            columns: [
              {
                width: 50, height: 50,
                canvas: [{ type: "rect", x: 0, y: 0, w: 50, h: 50, color: LIME, borderRadius: 12 }],
                stack: [{ text: "M", fontSize: 24, bold: true, color: DARK, alignment: "center", margin: [0, 14, 0, 0] }]
              },
              { width: 10, text: "" },
              {
                stack: [
                  { text: data.project.name, fontSize: 17, bold: true, color: "white", margin: [0, 4, 0, 0] },
                  { text: "LAUNCH TRACKER  ·  PROJECT REPORT", fontSize: 8, color: "#9eb2ae", letterSpacing: 1.5, margin: [0, 3, 0, 0] }
                ]
              }
            ],
            margin: [50, 50, 50, 0]
          },
          // cover centre
          {
            stack: [
              { text: "BUILD PHASE CONTROL REPORT", fontSize: 8, color: AQUA, bold: true, letterSpacing: 2, margin: [0, 70, 0, 12] },
              { text: data.project.name, fontSize: 46, bold: true, color: "white", lineHeight: 1.05, margin: [0, 0, 0, 20] },
              {
                text: `LOCATION · ${data.project.location || "Not set"}`,
                fontSize: 10, color: "#c7d5d2",
                margin: [0, 0, 0, 0]
              }
            ],
            margin: [50, 0, 50, 0]
          },
          // cover stats
          {
            columns: [
              { width: "auto", stack: [{ text: "OVERALL PROGRESS", fontSize: 8, color: "#8ca39e", letterSpacing: 1.5, margin: [0, 0, 0, 6] }, { text: `${overallProgress}%`, fontSize: 32, bold: true, color: "white" }] },
              { width: 40, text: "" },
              { width: "auto", stack: [{ text: "TASKS COMPLETED", fontSize: 8, color: "#8ca39e", letterSpacing: 1.5, margin: [0, 0, 0, 6] }, { text: `${completedCount}/${data.tasks.length}`, fontSize: 32, bold: true, color: "white" }] },
              { width: 40, text: "" },
              { width: "auto", stack: [{ text: "DAYS TO OPENING", fontSize: 8, color: "#8ca39e", letterSpacing: 1.5, margin: [0, 0, 0, 6] }, { text: `${daysRem ?? "—"}`, fontSize: 32, bold: true, color: "white" }, daysRem != null ? { text: fmt(data.project.openingDate, { day: "numeric", month: "long" }), fontSize: 9, color: LIME, margin: [0, 4, 0, 0] } : {}] }
            ],
            margin: [50, 60, 50, 0]
          },
          { text: `LOCATION · ${data.project.location || "Not set"}`, fontSize: 8, color: "#718984", margin: [50, 60, 50, 0] },
          { text: " ", margin: [0, 0, 0, 30] },

          // ── PAGE 2: EXECUTIVE SUMMARY ─────────────────────────────────
          { text: " ", margin: [0, 0, 0, 20] },
          ...makeSectionHead("WORK CONTROL", "Executive Summary"),

          // KPI row
          {
            columns: [
              { ...makeKPI("DAYS TO OPENING", daysRem ?? "—", `Target: ${fmt(data.project.openingDate)}`, { fillColor: DARK, width: "auto", labelColor: "#9eb2ae", valueColor: "#ffffff", noteColor: LIME }) },
              { width: 12, text: "" },
              { ...makeKPI("TASKS COMPLETED", `${completedCount}/${data.tasks.length}`, `${data.tasks.length ? Math.round(completedCount / data.tasks.length * 100) : 0}% done`) },
              { width: 12, text: "" },
              { ...makeKPI("OVERDUE TASKS", overdueTasks.length, overdueTasks.length ? "Needs attention" : "No delays") },
              { width: 12, text: "" },
              { ...makeKPI("OVERALL", `${overallProgress}%`, `${PHASES.length} phases tracked`) }
            ],
            margin: [0, 0, 0, 24]
          },

          // Overdue tasks alert
          ...(overdueTasks.length > 0 ? [
            {
              canvas: [{ type: "rect", x: 0, y: 0, w: 495, h: 38, color: "#fff0ee", borderRadius: 8 }],
              absolutePosition: { x: 50, y: 0 }
            },
            {
              table: {
                headerRows: 1,
                widths: [80, 150, 80, 100, 45],
                body: [
                  [{ text: "Phase", fontSize: 7, bold: true, color: DANGER, fillColor: "#fff0ee" },
                   { text: "Task", fontSize: 7, bold: true, color: DANGER, fillColor: "#fff0ee" },
                   { text: "Owner", fontSize: 7, bold: true, color: DANGER, fillColor: "#fff0ee" },
                   { text: "Deadline", fontSize: 7, bold: true, color: DANGER, fillColor: "#fff0ee" },
                   { text: "%", fontSize: 7, bold: true, color: DANGER, fillColor: "#fff0ee" }],
                  ...overdueTasks.map((t, i) => {
                    const ph = PHASES.find(p => p.id === t.phase);
                    return [
                      { text: ph ? `${ph.icon} ${ph.name}` : "—", fontSize: 8, fillColor: i % 2 ? "#fffaf9" : "white" },
                      { text: t.title, fontSize: 8, bold: true, fillColor: i % 2 ? "#fffaf9" : "white" },
                      { text: t.owner || "—", fontSize: 8, fillColor: i % 2 ? "#fffaf9" : "white" },
                      { text: fmtShort(t.deadline), fontSize: 8, color: DANGER, bold: true, fillColor: i % 2 ? "#fffaf9" : "white" },
                      { text: `${t.progress}%`, fontSize: 8, bold: true, fillColor: i % 2 ? "#fffaf9" : "white" }
                    ];
                  })
                ]
              },
              layout: {
                hLineWidth: () => 0.5,
                vLineWidth: () => 0,
                hLineColor: () => "#f1c9c5",
                borderRadius: 8,
                topPadding: () => 4,
                bottomPadding: () => 4
              },
              margin: [0, 0, 0, 24]
            }
          ] : []),

          // Phase Breakdown section
          ...makeSectionHead("OPENING ROADMAP", "Phase Breakdown"),
          ...PHASES.flatMap(phase => {
            const phaseTasks = data.tasks.filter(t => t.phase === phase.id);
            const avg = phaseTasks.length
              ? Math.round(phaseTasks.reduce((s, t) => s + Number(t.progress || 0), 0) / phaseTasks.length)
              : 0;
            const deadlines = phaseTasks.map(t => parseLocalDate(t.deadline)).filter(Boolean);
            const target = deadlines.length > 0
              ? fmt(new Date(Math.max(...deadlines.map(d => d.getTime()))).toISOString())
              : "Not set";

            return [
              // Phase header
              {
                columns: [
                  {
                    width: 36, height: 36,
                    canvas: [{ type: "rect", x: 0, y: 0, w: 36, h: 36, color: "#dff8f2", borderRadius: 9 }],
                    stack: [{ text: phase.icon, fontSize: 16, alignment: "center", margin: [0, 8, 0, 0] }]
                  },
                  { width: 10, text: "" },
                  { width: "*", stack: [
                    { text: phase.name, fontSize: 13, bold: true, color: INK },
                    { text: `${phaseTasks.length} task${phaseTasks.length !== 1 ? "s" : ""}  ·  Target: ${target}`, fontSize: 8, color: MUTED, margin: [0, 3, 0, 0] }
                  ]},
                  { width: "auto", stack: [
                    { text: `${avg}%`, fontSize: 20, bold: true, color: DARK, alignment: "right" },
                    {
                      canvas: [{ type: "rect", x: 0, y: 0, w: 100, h: 6, color: PAPER, borderRadius: 6 },
                               { type: "rect", x: 0, y: 0, w: avg, h: 6, color: AQUA, borderRadius: 6 }],
                      width: 100, height: 6, alignment: "right", margin: [0, 4, 0, 0]
                    }
                  ]}
                ],
                margin: [0, 0, 0, 10]
              },
              // Task table
              ...(phaseTasks.length > 0 ? [
                {
                  table: {
                    headerRows: 1,
                    widths: [85, 155, 85, 80, 50],
                    body: [
                      [{ text: "OWNER", fontSize: 7, bold: true, color: "#9aaba6" },
                       { text: "TASK", fontSize: 7, bold: true, color: "#9aaba6" },
                       { text: "DEADLINE", fontSize: 7, bold: true, color: "#9aaba6" },
                       { text: "STATUS", fontSize: 7, bold: true, color: "#9aaba6" },
                       { text: "PROGRESS", fontSize: 7, bold: true, color: "#9aaba6" }],
                      ...phaseTasks
                        .slice()
                        .sort((a, b) => String(a.deadline).localeCompare(String(b.deadline)))
                        .map((t, i) => {
                          const s = statusFor(t);
                          const sc = statusColor(s);
                          return [
                            { text: t.owner || "—", fontSize: 8, color: MUTED, fillColor: i % 2 ? PAPER : "white" },
                            { text: t.title, fontSize: 8, fillColor: i % 2 ? PAPER : "white" },
                            { text: fmtShort(t.deadline), fontSize: 8, fillColor: i % 2 ? PAPER : "white" },
                            { text: s, fontSize: 8, bold: true, color: sc.text, fillColor: sc.bg, alignment: "center" },
                            { text: `${t.progress}%`, fontSize: 8, bold: true, fillColor: i % 2 ? PAPER : "white" }
                          ];
                        })
                    ]
                  },
                  layout: {
                    hLineWidth: () => 0.3,
                    vLineWidth: () => 0,
                    hLineColor: () => LINE,
                    topPadding: () => 5,
                    bottomPadding: () => 5
                  },
                  margin: [0, 0, 0, 22]
                }
              ] : [{ text: "", margin: [0, 0, 0, 22] }])
            ];
          })
        ],

        footer(currentPage, pageCount) {
          return {
            text: `${data.project.name}  ·  Launch Tracker Report  ·  Page ${currentPage} of ${pageCount}  ·  Generated ${fmtDate()}`,
            fontSize: 7, color: MUTED, alignment: "center",
            margin: [50, 10, 50, 0]
          };
        },

        defaultStyle: { font: "Roboto", fontSize: 11, color: INK }
      };

      const filename = `mecardee-report-${new Date().toISOString().slice(0, 10)}.pdf`;
      pdfMake.createPdf(doc).download(filename);
      notify("Report downloaded!");
    } catch (err) {
      console.error("Export error:", err);
      notify("Could not generate report — try again.");
    } finally {
      setIsExporting(false);
    }
  }


  function beginTaskUpdate(task) {
    setTaskDrafts((current) => ({
      ...current,
      [task.id]: {
        progress: Number(task.progress || 0),
        actualCost: Number(task.actualCost || 0)
      }
    }));
  }

  function changeTaskDraft(id, patch) {
    setTaskDrafts((current) => ({
      ...current,
      [id]: {
        ...current[id],
        ...patch
      }
    }));
  }

  function cancelTaskUpdate(id) {
    setTaskDrafts((current) => {
      const next = { ...current };
      delete next[id];
      return next;
    });
  }

  async function saveTaskUpdate(task) {
    const draft = taskDrafts[task.id];
    if (!draft) return;

    const savedProgress = Number(task.progress || 0);
    const nextProgress = Math.max(savedProgress, Math.min(100, Number(draft.progress || savedProgress)));
    const nextActualCost = Math.max(0, Number(draft.actualCost || 0));

    setIsSyncing(true);
    const { error } = await supabase
      .from("mecardee_tasks")
      .update({
        progress: nextProgress,
        actual_cost: nextActualCost
      })
      .eq("id", task.id);
    setIsSyncing(false);

    if (error) {
      notify(`Could not save update: ${error.message}`);
      return;
    }

    setData((current) => ({
      ...current,
      tasks: current.tasks.map((item) => item.id === task.id
        ? { ...item, progress: nextProgress, actualCost: nextActualCost }
        : item)
    }));
    cancelTaskUpdate(task.id);
    notify("Task progress and spending updated.");
  }

  async function removeTask(id) {
    if (!window.confirm("Delete this task?")) return;
    cancelTaskUpdate(id);
    const previousTasks = data.tasks;
    setData((current) => ({ ...current, tasks: current.tasks.filter((task) => task.id !== id) }));
    setIsSyncing(true);

    const { error } = await supabase.from("mecardee_tasks").delete().eq("id", id);
    setIsSyncing(false);

    if (error) {
      setData((current) => ({ ...current, tasks: previousTasks }));
      notify(`Could not delete task: ${error.message}`);
      return;
    }
    notify("Task deleted from all devices.");
  }

  async function addTask(event) {
    event.preventDefault();
    if (!newTask.title.trim()) return;
    setIsSyncing(true);

    const { data: createdTask, error } = await supabase
      .from("mecardee_tasks")
      .insert({
        title: newTask.title.trim(),
        phase: newTask.phase,
        owner: newTask.owner.trim(),
        deadline: newTask.deadline,
        progress: Number(newTask.progress),
        expected_cost: Number(newTask.expectedCost || 0),
        actual_cost: 0,
        notes: newTask.notes.trim(),
        sort_order: data.tasks.length * 10 + 10
      })
      .select("*")
      .single();

    setIsSyncing(false);
    if (error) {
      notify(`Could not add task: ${error.message}`);
      return;
    }

    setData((current) => ({
      ...current,
      tasks: [...current.tasks.filter((task) => task.id !== createdTask.id), mapTask(createdTask)]
    }));
    setNewTask({ title: "", phase: "site", owner: "", deadline: dateFromNow(7), progress: 0, expectedCost: 0, notes: "" });
    setShowTaskModal(false);
    notify("New task saved for all devices.");
  }

  async function saveProject(event) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const project = {
      name: String(form.get("name") || "Mecardee Car Wash"),
      location: String(form.get("location") || "Kerala, India"),
      openingDate: String(form.get("openingDate") || ""),
      totalBudget: Number(form.get("totalBudget") || 0),
      phaseBudgets: Object.fromEntries(
        PHASES.map((phase) => [phase.id, Number(form.get(`phaseBudget_${phase.id}`) || 0)])
      )
    };

    setIsSyncing(true);
    const { error } = await supabase.from("mecardee_project").upsert({
      id: 1,
      name: project.name,
      location: project.location,
      opening_date: project.openingDate,
      total_budget: project.totalBudget,
      phase_budgets: project.phaseBudgets
    });
    setIsSyncing(false);

    if (error) {
      notify(`Could not save settings: ${error.message}`);
      return;
    }

    setData((current) => ({ ...current, project }));
    setShowSettings(false);
    notify("Project details saved.");
  }

  if (!authChecked) {
    return (
      <main className="loading-screen">
        <div className="brand-mark">M</div>
        <p>Opening Mecardee…</p>
      </main>
    );
  }

  if (!isLoggedIn) {
    return (
      <main className="login-screen">
        <section className="login-card">
          <div className="brand-mark login-logo">M</div>
          <span className="eyebrow">Private project tracker</span>
          <h1>Mecardee Car Wash</h1>
          <p>Sign in to view construction, deadlines and budgets.</p>
          <form onSubmit={handleLogin} className="login-form">
            <label>Username
              <input name="username" autoComplete="username" autoFocus required />
            </label>
            <label>Password
              <input name="password" type="password" autoComplete="current-password" required />
            </label>
            {loginError && <div className="login-error">{loginError}</div>}
            <button className="primary-button" type="submit">Sign in</button>
          </form>
        </section>
      </main>
    );
  }

  if (!data) {
    return (
      <main className="loading-screen">
        <div className="brand-mark">M</div>
        {loadError ? (
          <div className="database-error">
            <strong>Database setup required</strong>
            <p>{loadError}</p>
            <button className="primary-button" onClick={() => loadData()}>Retry connection</button>
          </div>
        ) : (
          <p>Connecting to Mecardee…</p>
        )}
      </main>
    );
  }

  const visibleTasks = activePhase === "all" ? data.tasks : data.tasks.filter((task) => task.phase === activePhase);

  return (
    <main className="app-shell">
      <header className="topbar">
        <a className="brand" href="#top" aria-label="Mecardee home">
          <span className="brand-mark logo-image"><img src="/mecardee-logo.png" alt="Mecardee Car Wash logo" /></span>
          <span>
            <strong>{data.project.name}</strong>
            <small>Launch tracker</small>
          </span>
        </a>
        <div className="top-actions">
          <span className={`sync-pill ${isSyncing ? "syncing" : ""}`}><i />{isSyncing ? "Saving" : "Live"}</span>
          <button className="notification-button" onClick={() => setShowAlerts((value) => !value)} aria-label="Open alerts">
            <span>♢</span>
            {alerts.length > 0 && <b>{alerts.length}</b>}
          </button>
          <button className="export-button" onClick={handleExportReport} disabled={isExporting} aria-label="Export report as PDF">
            {isExporting ? "Generating…" : "↓ Export PDF"}
          </button>
          <button
            className="settings-button"
            type="button"
            onClick={() => {
              setAccountMessage("");
              setShowAccountSettings(true);
            }}
            aria-label="User settings"
            title="User settings"
          >
            <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
              <path d="M12 15.25A3.25 3.25 0 1 0 12 8.75a3.25 3.25 0 0 0 0 6.5Z" />
              <path d="M19.1 13.2a7.8 7.8 0 0 0 .05-1.2 7.8 7.8 0 0 0-.05-1.2l2-1.55-2-3.46-2.48 1a8.38 8.38 0 0 0-2.07-1.2L14.2 3h-4.4l-.35 2.59c-.74.29-1.43.69-2.07 1.2l-2.48-1-2 3.46 2 1.55a7.8 7.8 0 0 0-.05 1.2c0 .4.02.8.05 1.2l-2 1.55 2 3.46 2.48-1c.64.51 1.33.91 2.07 1.2L9.8 21h4.4l.35-2.59a8.38 8.38 0 0 0 2.07-1.2l2.48 1 2-3.46-2-1.55Z" />
            </svg>
          </button>
          <button className="secondary-button logout-button" onClick={logout}>Log out</button>
          <button className="primary-button" onClick={() => setShowTaskModal(true)}>＋ Add task</button>
        </div>

        {showAlerts && (
          <aside className="alerts-popover">
            <div className="popover-head">
              <div>
                <span className="eyebrow">Deadline centre</span>
                <h3>{alerts.length ? `${alerts.length} alert${alerts.length === 1 ? "" : "s"}` : "Everything is on track"}</h3>
              </div>
              <button className="icon-button" onClick={() => setShowAlerts(false)}>×</button>
            </div>
            <div className="alert-list">
              {alerts.length === 0 ? (
                <div className="empty-state compact">
                  <span>✓</span>
                  <p>No overdue or near-deadline tasks.</p>
                </div>
              ) : alerts.map((alert, index) => (
                <div className={`alert-row ${alert.level}`} key={`${alert.title}-${index}`}>
                  <i />
                  <div><strong>{alert.title}</strong><span>{alert.detail}</span></div>
                </div>
              ))}
            </div>
            <p className="session-note">These alerts are calculated from the shared Supabase deadlines.</p>
          </aside>
        )}
      </header>

      <section className="hero" id="top">
        <div className="hero-copy">
          <span className="location-pill">⌖ {data.project.location}</span>
          <p className="eyebrow light">BUILD PHASE CONTROL</p>
          <h1>From construction<br />to the first clean car.</h1>
          <p className="hero-subtitle">One simple view for the work, deadlines and opening readiness of Mecardee Car Wash.</p>
          <div className="hero-actions">
            <button className="light-button" onClick={() => setShowTaskModal(true)}>Add today’s work</button>
            <button className="ghost-button" onClick={() => document.getElementById("tasks")?.scrollIntoView({ behavior: "smooth" })}>View all tasks ↓</button>
          </div>
        </div>

        <div className="hero-status">
          <ProgressRing value={overallProgress} />
          <div className="opening-meta">
            <span>Target opening</span>
            <strong>{formatDate(data.project.openingDate, { day: "numeric", month: "long", year: "numeric" })}</strong>
            <small>{openingDays} days remaining</small>
          </div>
        </div>
      </section>

      <section className="summary-grid" aria-label="Project summary">
        <button type="button" className="summary-card emphasized" onClick={() => setActiveSummary("opening")}>
          <span className="summary-icon">◴</span>
          <div><small>Days to opening</small><strong>{openingDays}</strong></div>
          <p>Target: {formatDate(data.project.openingDate, { day: "numeric", month: "short" })}</p>
          <span className="summary-expand">View details ↗</span>
        </button>
        <button type="button" className="summary-card" onClick={() => setActiveSummary("completed")}>
          <span className="summary-icon">✓</span>
          <div><small>Tasks completed</small><strong>{completedTasks}<em>/{data.tasks.length}</em></strong></div>
          <p>{taskCompletionPercent}% of the checklist</p>
          <span className="summary-expand">View details ↗</span>
        </button>
        <button type="button" className={`summary-card ${overdueTasks ? "danger-card" : ""}`} onClick={() => setActiveSummary("overdue")}>
          <span className="summary-icon">!</span>
          <div><small>Overdue work</small><strong>{overdueTasks}</strong></div>
          <p>{overdueTasks ? "Needs attention now" : "No delayed tasks"}</p>
          <span className="summary-expand">View details ↗</span>
        </button>
        <button type="button" className="summary-card" onClick={() => setActiveSummary("phases")}>
          <span className="summary-icon">▤</span>
          <div><small>Active phases</small><strong>{activePhaseCount}</strong></div>
          <p>{PHASES.length} phases in the plan</p>
          <span className="summary-expand">View details ↗</span>
        </button>
      </section>

      <section className="section-block budget-section" id="budget">
        <div className="section-heading">
          <div>
            <span className="eyebrow">Money control</span>
            <h2>Total budget</h2>
          </div>
          <button className="text-button" onClick={() => setShowSettings(true)}>Edit budgets →</button>
        </div>

        <div className="budget-summary-grid">
          <article className="budget-summary-card primary-budget">
            <small>Total available budget</small>
            <strong>{formatMoney(totalBudget)}</strong>
          </article>
          <article className="budget-summary-card">
            <small>Expected task cost</small>
            <strong>{formatMoney(totalExpected)}</strong>
          </article>
          <article className="budget-summary-card">
            <small>Actual amount spent</small>
            <strong>{formatMoney(totalSpent)}</strong>
          </article>
          <article className={`budget-summary-card ${totalAvailable < 0 ? "over-budget" : ""}`}>
            <small>Budget remaining</small>
            <strong>{formatMoney(totalAvailable)}</strong>
          </article>
        </div>

        <div className="phase-budget-grid">
          {PHASES.map((phase) => {
            const stat = phaseStats[phase.id] || { budget: 0, spent: 0, available: 0 };
            return (
              <article className="phase-budget-card" key={phase.id}>
                <div><span className="phase-icon small-phase-icon">{phase.icon}</span><strong>{phase.name}</strong></div>
                <dl>
                  <div><dt>Budget</dt><dd>{formatMoney(stat.budget)}</dd></div>
                  <div><dt>Spent</dt><dd>{formatMoney(stat.spent)}</dd></div>
                  <div className={stat.available < 0 ? "negative-budget" : ""}><dt>Available</dt><dd>{formatMoney(stat.available)}</dd></div>
                </dl>
              </article>
            );
          })}
        </div>
      </section>

      <section className="section-block">
        <div className="section-heading">
          <div>
            <span className="eyebrow">Opening roadmap</span>
            <h2>Phase completion</h2>
          </div>
          <button className="text-button" onClick={() => setShowSettings(true)}>Project settings →</button>
        </div>

        <div className="phase-grid">
          {PHASES.map((phase, index) => {
            const stat = phaseStats[phase.id] || { progress: 0, count: 0, target: null };
            return (
              <button
                key={phase.id}
                className={`phase-card ${activePhase === phase.id ? "selected" : ""}`}
                onClick={() => {
                  setActivePhase(phase.id);
                  document.getElementById("tasks")?.scrollIntoView({ behavior: "smooth" });
                }}
              >
                <div className="phase-top">
                  <span className="phase-number">{pad(index + 1)}</span>
                  <span className="phase-icon">{phase.icon}</span>
                </div>
                <h3>{phase.name}</h3>
                <p>{stat.count} task{stat.count === 1 ? "" : "s"} · Target {stat.target ? new Intl.DateTimeFormat("en-IN", { day: "numeric", month: "short" }).format(stat.target) : "not set"}</p>
                <div className="phase-cost-line"><span>Available budget</span><strong>{formatMoney(stat.available)}</strong></div>
                <div className="mini-progress"><i style={{ width: `${stat.progress}%` }} /></div>
                <strong className="phase-percent">{stat.progress}%</strong>
              </button>
            );
          })}
        </div>
      </section>

      <section className="section-block tasks-section" id="tasks">
        <div className="section-heading task-heading">
          <div>
            <span className="eyebrow">Work control</span>
            <h2>{activePhase === "all" ? "All project tasks" : PHASES.find((phase) => phase.id === activePhase)?.name}</h2>
          </div>
          <div className="filter-row">
            <button className={activePhase === "all" ? "filter active" : "filter"} onClick={() => setActivePhase("all")}>All</button>
            {PHASES.map((phase) => (
              <button key={phase.id} className={activePhase === phase.id ? "filter active" : "filter"} onClick={() => setActivePhase(phase.id)}>{phase.short}</button>
            ))}
          </div>
        </div>

        <div className="task-list">
          {visibleTasks.length === 0 ? (
            <div className="empty-state">
              <span>＋</span>
              <h3>No tasks in this phase</h3>
              <p>Add the next piece of work and assign its deadline.</p>
              <button className="primary-button" onClick={() => setShowTaskModal(true)}>Add task</button>
            </div>
          ) : visibleTasks
            .slice()
            .sort((a, b) => String(a.deadline).localeCompare(String(b.deadline)))
            .map((task) => {
              const status = statusFor(task);
              const phase = PHASES.find((item) => item.id === task.phase);
              return (
                <article className="task-card" key={task.id}>
                  <div className="task-main">
                    <div className={`status-dot ${status.toLowerCase().replace(" ", "-")}`} />
                    <div className="task-copy">
                      <div className="task-meta">
                        <span>{phase?.icon} {phase?.name}</span>
                        <span className={`status-badge ${status.toLowerCase().replace(" ", "-")}`}>{status}</span>
                      </div>
                      <h3>{task.title}</h3>
                      {task.notes && <p>{task.notes}</p>}
                      <div className="task-details">
                        <span>👤 {task.owner || "Not assigned"}</span>
                        <span>◷ {formatDate(task.deadline)}</span>
                        <span>Expected: {formatMoney(task.expectedCost)}</span>
                        <span>Spent: {formatMoney(task.actualCost)}</span>
                      </div>
                    </div>
                  </div>

                  <div className={`task-progress-control ${taskDrafts[task.id] ? "editing" : ""}`}>
                    {taskDrafts[task.id] ? (
                      <>
                        <div className="range-label">
                          <span>Update progress</span>
                          <strong>{taskDrafts[task.id].progress}%</strong>
                        </div>
                        <label className="actual-cost-field">Actual amount spent
                          <input
                            type="number"
                            min="0"
                            step="1"
                            value={taskDrafts[task.id].actualCost}
                            onChange={(event) => changeTaskDraft(task.id, { actualCost: Number(event.target.value || 0) })}
                            aria-label={`Actual amount spent for ${task.title}`}
                          />
                        </label>
                        <input
                          type="range"
                          min={Number(task.progress || 0)}
                          max="100"
                          step="5"
                          value={taskDrafts[task.id].progress}
                          onChange={(event) => changeTaskDraft(task.id, {
                            progress: Math.max(Number(task.progress || 0), Number(event.target.value))
                          })}
                          aria-label={`Forward-only progress for ${task.title}`}
                        />
                        <p className="progress-lock-note">
                          Saved progress is {task.progress}%. This slider can only move forward.
                        </p>
                        <div className="task-buttons update-actions">
                          <button
                            type="button"
                            className="secondary-task-button"
                            onClick={() => changeTaskDraft(task.id, { progress: 100 })}
                          >
                            Set 100%
                          </button>
                          <button type="button" className="secondary-task-button" onClick={() => cancelTaskUpdate(task.id)}>
                            Cancel
                          </button>
                          <button
                            type="button"
                            className="small-button save-update-button"
                            disabled={isSyncing}
                            onClick={() => saveTaskUpdate(task)}
                          >
                            {isSyncing ? "Saving…" : "Save update"}
                          </button>
                        </div>
                      </>
                    ) : (
                      <>
                        <div className="saved-progress-row">
                          <div>
                            <span>Current progress</span>
                            <strong>{task.progress}%</strong>
                          </div>
                          <div>
                            <span>Amount spent</span>
                            <strong>{formatMoney(task.actualCost)}</strong>
                          </div>
                        </div>
                        <div className="locked-progress-track" aria-hidden="true">
                          <i style={{ width: `${task.progress}%` }} />
                        </div>
                        <div className="task-buttons">
                          <button type="button" className="small-button update-task-button" onClick={() => beginTaskUpdate(task)}>
                            Update
                          </button>
                          <button type="button" className="delete-button" onClick={() => removeTask(task.id)} aria-label={`Delete ${task.title}`}>
                            Delete
                          </button>
                        </div>
                      </>
                    )}
                  </div>
                </article>
              );
            })}
        </div>
      </section>

      <nav className="mobile-nav" aria-label="Mobile navigation">
        <a href="#top"><span>⌂</span><small>Home</small></a>
        <a href="#budget"><span>₹</span><small>Budget</small></a>
        <a href="#tasks"><span>✓</span><small>Tasks</small></a>
        <button type="button" onClick={() => setShowTaskModal(true)}><span>＋</span><small>Add</small></button>
      </nav>

      <footer>
        <div className="brand footer-brand"><span className="brand-mark logo-image"><img src="/mecardee-logo.png" alt="Mecardee Car Wash logo" /></span><span><strong>Mecardee Car Wash</strong><small>Built for a smooth opening.</small></span></div>
        <p>Connected to Supabase. Changes sync across phones and computers.</p>
      </footer>

      {activeSummary && (
        <Modal
          title={
            activeSummary === "opening" ? "Opening countdown" :
            activeSummary === "completed" ? "Completed tasks" :
            activeSummary === "overdue" ? "Overdue work" :
            "Active phases"
          }
          onClose={() => setActiveSummary(null)}
        >
          <div className="summary-popup">
            {activeSummary === "opening" && (
              <>
                <div className="popup-hero-metric">
                  <span>{openingDays}</span>
                  <div><strong>days remaining</strong><small>Target {formatDate(data.project.openingDate, { day: "numeric", month: "long", year: "numeric" })}</small></div>
                </div>
                <div className="popup-progress"><i style={{ width: `${overallProgress}%` }} /></div>
                <p>The whole project is currently {overallProgress}% complete.</p>
              </>
            )}

            {activeSummary === "completed" && (
              <>
                <div className="popup-hero-metric">
                  <span>{completedTasks}</span>
                  <div><strong>tasks completed</strong><small>{taskCompletionPercent}% of {data.tasks.length} tasks</small></div>
                </div>
                <div className="popup-list">
                  {completedTaskList.length ? completedTaskList.map((task) => (
                    <div key={task.id}><strong>{task.title}</strong><span>{formatMoney(task.actualCost)} spent</span></div>
                  )) : <p>No task has been completed yet.</p>}
                </div>
              </>
            )}

            {activeSummary === "overdue" && (
              <>
                <div className={`popup-hero-metric ${overdueTasks ? "danger-popup" : ""}`}>
                  <span>{overdueTasks}</span>
                  <div><strong>{overdueTasks ? "tasks need attention" : "no delayed work"}</strong><small>Based on current deadlines</small></div>
                </div>
                <div className="popup-list">
                  {overdueTaskList.length ? overdueTaskList.map((task) => (
                    <button
                      type="button"
                      key={task.id}
                      onClick={() => {
                        setActivePhase(task.phase);
                        setActiveSummary(null);
                        window.setTimeout(() => document.getElementById("tasks")?.scrollIntoView({ behavior: "smooth" }), 80);
                      }}
                    >
                      <strong>{task.title}</strong>
                      <span>Due {formatDate(task.deadline)}</span>
                    </button>
                  )) : <p>Every incomplete task is still within its deadline.</p>}
                </div>
              </>
            )}

            {activeSummary === "phases" && (
              <>
                <div className="popup-hero-metric">
                  <span>{activePhaseCount}</span>
                  <div><strong>phases currently active</strong><small>{PHASES.length} phases in the opening plan</small></div>
                </div>
                <div className="popup-list">
                  {activePhaseList.length ? activePhaseList.map((phase) => (
                    <button
                      type="button"
                      key={phase.id}
                      onClick={() => {
                        setActivePhase(phase.id);
                        setActiveSummary(null);
                        window.setTimeout(() => document.getElementById("tasks")?.scrollIntoView({ behavior: "smooth" }), 80);
                      }}
                    >
                      <strong>{phase.name}</strong>
                      <span>{phaseStats[phase.id]?.progress || 0}% complete</span>
                    </button>
                  )) : <p>No phase is currently between 1% and 99% progress.</p>}
                </div>
              </>
            )}
          </div>
        </Modal>
      )}

      {showTaskModal && (
        <Modal title="Add a project task" onClose={() => setShowTaskModal(false)}>
          <form className="form-grid" onSubmit={addTask}>
            <label className="full-field">Task name
              <input required autoFocus value={newTask.title} onChange={(event) => setNewTask({ ...newTask, title: event.target.value })} placeholder="Example: Complete wash-bay flooring" />
            </label>
            <label>Project phase
              <select value={newTask.phase} onChange={(event) => setNewTask({ ...newTask, phase: event.target.value })}>
                {PHASES.map((phase) => <option value={phase.id} key={phase.id}>{phase.name}</option>)}
              </select>
            </label>
            <label>Responsible person
              <input value={newTask.owner} onChange={(event) => setNewTask({ ...newTask, owner: event.target.value })} placeholder="Owner / contractor" />
            </label>
            <label>Deadline
              <input required type="date" value={newTask.deadline} onChange={(event) => setNewTask({ ...newTask, deadline: event.target.value })} />
            </label>
            <label>Starting progress
              <select value={newTask.progress} onChange={(event) => setNewTask({ ...newTask, progress: Number(event.target.value) })}>
                <option value="0">0% · Not started</option>
                <option value="25">25% · Started</option>
                <option value="50">50% · Halfway</option>
                <option value="75">75% · Nearly done</option>
                <option value="100">100% · Complete</option>
              </select>
            </label>
            <label>Expected cost (₹)
              <input type="number" min="0" step="1" value={newTask.expectedCost} onChange={(event) => setNewTask({ ...newTask, expectedCost: Number(event.target.value || 0) })} placeholder="0" />
            </label>
            <label className="full-field">Notes
              <textarea value={newTask.notes} onChange={(event) => setNewTask({ ...newTask, notes: event.target.value })} placeholder="Important measurement, dependency or instruction…" />
            </label>
            <div className="modal-actions full-field">
              <button type="button" className="secondary-button" onClick={() => setShowTaskModal(false)}>Cancel</button>
              <button className="primary-button" type="submit">Add task</button>
            </div>
          </form>
        </Modal>
      )}


      {showAccountSettings && (
        <Modal title="User settings" onClose={() => setShowAccountSettings(false)}>
          <div className="user-settings-panel">
            <div className="current-user-card">
              <div className="user-avatar">{String(currentUser?.username || "U").slice(0, 1).toUpperCase()}</div>
              <div>
                <span>Signed in as</span>
                <strong>{currentUser?.username}</strong>
                <small>{currentUser?.isAdmin ? "Administrator" : "User"}</small>
              </div>
            </div>

            {accountMessage && <div className="account-message">{accountMessage}</div>}

            <section className="account-setting-section">
              <div className="account-section-heading">
                <span>01</span>
                <div>
                  <h3>Change my password</h3>
                  <p>Update the password for {currentUser?.username}.</p>
                </div>
              </div>

              <form className="account-form" onSubmit={changeCurrentPassword}>
                <label>Current password
                  <input name="currentPassword" type="password" autoComplete="current-password" required />
                </label>
                <label>New password
                  <input name="changedPassword" type="password" minLength="4" autoComplete="new-password" required />
                </label>
                <label>Confirm new password
                  <input name="confirmChangedPassword" type="password" minLength="4" autoComplete="new-password" required />
                </label>
                <button className="primary-button" type="submit" disabled={accountBusy}>
                  {accountBusy ? "Savingâ€¦" : "Change password"}
                </button>
              </form>
            </section>

            {currentUser?.isAdmin && (
              <section className="account-setting-section admin-user-section">
                <div className="account-section-heading">
                  <span>02</span>
                  <div>
                    <h3>Add a new user</h3>
                    <p>New users get the same tracker options as Delvin.</p>
                  </div>
                </div>

                <form className="account-form" onSubmit={addNewUser}>
                  <label>Username
                    <input name="newUsername" minLength="3" pattern="[a-zA-Z0-9._-]+" autoComplete="off" required />
                  </label>
                  <label>Password
                    <input name="newPassword" type="password" minLength="4" autoComplete="new-password" required />
                  </label>
                  <label>Confirm password
                    <input name="confirmNewPassword" type="password" minLength="4" autoComplete="new-password" required />
                  </label>
                  <button className="primary-button" type="submit" disabled={accountBusy}>
                    {accountBusy ? "Creatingâ€¦" : "Add user"}
                  </button>
                </form>
              </section>
            )}
          </div>
        </Modal>
      )}

      {showSettings && (
        <Modal title="Project settings" onClose={() => setShowSettings(false)}>
          <form className="form-grid" onSubmit={saveProject}>
            <label className="full-field">Business name
              <input name="name" defaultValue={data.project.name} required />
            </label>
            <label>Location
              <input name="location" defaultValue={data.project.location} />
            </label>
            <label>Target opening date
              <input name="openingDate" type="date" defaultValue={data.project.openingDate} required />
            </label>
            <label>Total project budget (₹)
              <input name="totalBudget" type="number" min="0" step="1" defaultValue={data.project.totalBudget} />
            </label>
            <div className="phase-budget-form full-field">
              <strong>Budget available for each phase</strong>
              <div className="phase-budget-inputs">
                {PHASES.map((phase) => (
                  <label key={phase.id}>{phase.name}
                    <input
                      name={`phaseBudget_${phase.id}`}
                      type="number"
                      min="0"
                      step="1"
                      defaultValue={data.project.phaseBudgets?.[phase.id] || 0}
                    />
                  </label>
                ))}
              </div>
            </div>
            <div className="frontend-note full-field">
              These settings are saved to Supabase and appear on every device using this app.
            </div>
            <div className="modal-actions split-actions full-field">
              <button type="button" className="text-button" onClick={() => loadData()}>Refresh data</button>
              <div>
                <button type="button" className="secondary-button" onClick={() => setShowSettings(false)}>Cancel</button>
                <button className="primary-button" type="submit">Save changes</button>
              </div>
            </div>
          </form>
        </Modal>
      )}

      {toast && <div className="toast">{toast}</div>}
    </main>
  );
}
