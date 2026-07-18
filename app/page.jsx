"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { supabase } from "../lib/supabase";
import pdfMake from "pdfmake/build/pdfmake";
import pdfFonts from "pdfmake/build/vfs_fonts";

pdfMake.vfs = pdfFonts;

// MECARDEE_CATEGORIES_REPORTS_PERMISSIONS_V1
const USER_SESSION_KEY = "mecardee-user-session";
const PAGE_SIZE = 25;

const pad = (value) => String(value).padStart(2, "0");

function toDateInput(value = new Date()) {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function dateFromNow(days) {
  const date = new Date();
  date.setHours(12, 0, 0, 0);
  date.setDate(date.getDate() + days);
  return toDateInput(date);
}

function parseLocalDate(value) {
  if (!value) return null;
  const date = new Date(`${value}T12:00:00`);
  return Number.isNaN(date.getTime()) ? null : date;
}

function formatDate(value, options = { day: "numeric", month: "short", year: "numeric" }) {
  const date = parseLocalDate(value);
  if (!date) return "No date";
  return new Intl.DateTimeFormat("en-IN", options).format(date);
}

function formatMonth(value) {
  const date = parseLocalDate(`${value}-01`);
  if (!date) return value || "—";
  return new Intl.DateTimeFormat("en-IN", { month: "short", year: "numeric" }).format(date);
}

function formatMoney(value) {
  return new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    maximumFractionDigits: 0
  }).format(Number(value || 0));
}

function formatPlainMoney(value) {
  return new Intl.NumberFormat("en-IN", {
    maximumFractionDigits: 0
  }).format(Number(value || 0));
}

function startOfToday() {
  const date = new Date();
  date.setHours(0, 0, 0, 0);
  return date;
}

function daysBetween(from, to) {
  return Math.ceil((to.getTime() - from.getTime()) / 86400000);
}

function workStatus(work) {
  if (work.isCompleted) return "Completed";
  const deadline = parseLocalDate(work.deadline);
  if (deadline && deadline < startOfToday()) return "Overdue";
  return "Open";
}

function workAlert(work) {
  if (work.isCompleted) return null;
  const deadline = parseLocalDate(work.deadline);
  if (!deadline) return null;
  const days = daysBetween(startOfToday(), deadline);
  if (days < 0) {
    const late = Math.abs(days);
    return {
      level: "danger",
      title: `${work.title} is overdue`,
      detail: `${late} day${late === 1 ? "" : "s"} late · ${work.owner || "No owner"}`
    };
  }
  if (days === 0) {
    return { level: "danger", title: `${work.title} is due today`, detail: work.owner || "No owner" };
  }
  if (days <= 3) {
    return {
      level: "warning",
      title: `${work.title} is due soon`,
      detail: `${days} day${days === 1 ? "" : "s"} remaining · ${work.owner || "No owner"}`
    };
  }
  return null;
}

function mapProject(row) {
  return {
    name: row?.name || "Mecardee Car Wash",
    location: row?.location || "Kerala, India",
    openingDate: row?.opening_date || dateFromNow(100)
  };
}

function mapCategory(row) {
  return {
    id: row.id,
    name: row.name,
    icon: row.icon || "•",
    sortOrder: Number(row.sort_order || 0),
    budget: Number(row.budget || 0),
    completion: Number(row.completion || 0),
    isActive: Boolean(row.is_active)
  };
}

function mapWork(row) {
  return {
    id: row.id,
    title: row.title,
    categoryId: row.phase,
    owner: row.owner || "",
    workDate: row.work_date || row.created_at?.slice(0, 10) || toDateInput(),
    deadline: row.deadline,
    isCompleted: Boolean(row.is_completed ?? Number(row.progress || 0) >= 100),
    entryType: row.entry_type || "Work",
    amount: Number(row.amount || row.actual_cost || 0),
    notes: row.notes || "",
    sortOrder: Number(row.sort_order || 0)
  };
}

function mapTransaction(row) {
  return {
    id: row.id,
    sortOrder: Number(row.sort_order || 0),
    date: row.txn_date,
    type: row.txn_type,
    description: row.description,
    categoryId: row.category_id,
    amount: Number(row.amount || 0),
    notes: row.notes || "",
    workId: row.work_id || null
  };
}

function mapShareholder(row) {
  return {
    id: row.id,
    name: row.name,
    amount: Number(row.amount || 0),
    sortOrder: Number(row.sort_order || 0)
  };
}

async function fetchTrackerData() {
  const [projectResult, categoryResult, workResult, transactionResult, shareholderResult] = await Promise.all([
    supabase.from("mecardee_project").select("*").eq("id", 1).maybeSingle(),
    supabase.from("mecardee_categories").select("*").order("sort_order", { ascending: true }).order("name", { ascending: true }),
    supabase.from("mecardee_tasks").select("*").order("work_date", { ascending: false }).order("sort_order", { ascending: true }),
    supabase.from("mecardee_transactions").select("*").order("txn_date", { ascending: true }).order("sort_order", { ascending: true }),
    supabase.from("mecardee_shareholders").select("*").order("sort_order", { ascending: true }).order("name", { ascending: true })
  ]);

  const firstError = [
    projectResult.error,
    categoryResult.error,
    workResult.error,
    transactionResult.error,
    shareholderResult.error
  ].find(Boolean);

  if (firstError) throw firstError;

  return {
    project: mapProject(projectResult.data),
    categories: (categoryResult.data || []).map(mapCategory),
    works: (workResult.data || []).map(mapWork),
    transactions: (transactionResult.data || []).map(mapTransaction),
    shareholders: (shareholderResult.data || []).map(mapShareholder)
  };
}

function Modal({ title, eyebrow = "Mecardee tracker", children, onClose, wide = false }) {
  useEffect(() => {
    const close = (event) => event.key === "Escape" && onClose();
    window.addEventListener("keydown", close);
    return () => window.removeEventListener("keydown", close);
  }, [onClose]);

  return (
    <div className="modal-backdrop" onMouseDown={(event) => event.target === event.currentTarget && onClose()}>
      <section className={`modal-card ${wide ? "wide-modal" : ""}`} role="dialog" aria-modal="true" aria-label={title}>
        <div className="modal-head">
          <div>
            <span className="eyebrow">{eyebrow}</span>
            <h2>{title}</h2>
          </div>
          <button className="icon-button" type="button" onClick={onClose} aria-label="Close">×</button>
        </div>
        {children}
      </section>
    </div>
  );
}

function CompletionDonut({ value, label = "Category completion", size = 174 }) {
  const safeValue = Math.max(0, Math.min(100, Number(value || 0)));
  return (
    <div
      className="category-donut"
      style={{
        "--donut-value": `${safeValue * 3.6}deg`,
        width: size,
        height: size
      }}
      aria-label={`${label}: ${safeValue}%`}
    >
      <div>
        <strong>{safeValue}%</strong>
        <span>{label}</span>
      </div>
    </div>
  );
}

function emptyWork(categories) {
  return {
    id: null,
    title: "",
    categoryId: categories.find((category) => category.isActive)?.id || "",
    owner: "",
    workDate: toDateInput(),
    deadline: dateFromNow(7),
    isCompleted: false,
    entryType: "Work",
    amount: 0,
    notes: "",
    sortOrder: 0
  };
}

export default function Home() {
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const [currentUser, setCurrentUser] = useState(null);
  const [authChecked, setAuthChecked] = useState(false);
  const [loginError, setLoginError] = useState("");
  const [accountBusy, setAccountBusy] = useState(false);
  const [accountMessage, setAccountMessage] = useState("");
  const [data, setData] = useState(null);
  const [isSyncing, setIsSyncing] = useState(false);
  const [loadError, setLoadError] = useState("");
  const [toast, setToast] = useState("");
  const [isExporting, setIsExporting] = useState(false);
  const [showAlerts, setShowAlerts] = useState(false);
  const [modal, setModal] = useState("");
  const [workDraft, setWorkDraft] = useState(null);
  const [activeCategory, setActiveCategory] = useState("all");
  const [workStatusFilter, setWorkStatusFilter] = useState("all");
  const [transactionFilters, setTransactionFilters] = useState({
    from: "",
    to: "",
    type: "all",
    category: "all",
    search: ""
  });
  const [transactionPage, setTransactionPage] = useState(1);

  const isAdmin = Boolean(currentUser?.isAdmin && currentUser?.username === "delvin");

  const notify = useCallback((message) => {
    setToast(message);
    window.setTimeout(() => setToast(""), 2600);
  }, []);

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
          ? "The new categories/report migration has not been pushed yet. Run supabase db push and retry."
          : error?.message || "Could not connect to the Mecardee database."
      );
    } finally {
      if (!quiet) setIsSyncing(false);
    }
  }, []);

  useEffect(() => {
    if (!isLoggedIn) return undefined;

    loadData();

    const channel = supabase.channel("mecardee-category-report-live");
    ["mecardee_project", "mecardee_categories", "mecardee_tasks", "mecardee_transactions", "mecardee_shareholders"].forEach((table) => {
      channel.on("postgres_changes", { event: "*", schema: "public", table }, () => loadData({ quiet: true }));
    });
    channel.subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [isLoggedIn, loadData]);

  const activeCategories = useMemo(
    () => data?.categories.filter((category) => category.isActive) || [],
    [data]
  );

  const categoryById = useMemo(
    () => Object.fromEntries((data?.categories || []).map((category) => [category.id, category])),
    [data]
  );

  const report = useMemo(() => {
    const transactions = data?.transactions || [];
    const expenses = transactions.filter((transaction) => transaction.type === "Expense");
    const credits = transactions.filter((transaction) => transaction.type === "Credit");
    const totalExpenses = expenses.reduce((sum, transaction) => sum + transaction.amount, 0);
    const totalCredits = credits.reduce((sum, transaction) => sum + transaction.amount, 0);

    const categoryTotals = Object.fromEntries(activeCategories.map((category) => [category.id, 0]));
    expenses.forEach((transaction) => {
      if (transaction.categoryId) {
        categoryTotals[transaction.categoryId] = Number(categoryTotals[transaction.categoryId] || 0) + transaction.amount;
      }
    });

    const categories = activeCategories
      .map((category) => ({
        ...category,
        spent: Number(categoryTotals[category.id] || 0),
        available: category.budget - Number(categoryTotals[category.id] || 0),
        share: totalExpenses ? (Number(categoryTotals[category.id] || 0) / totalExpenses) * 100 : 0
      }))
      .sort((a, b) => b.spent - a.spent);

    const monthMap = new Map();
    transactions.forEach((transaction) => {
      const month = String(transaction.date || "").slice(0, 7);
      if (!month) return;
      const current = monthMap.get(month) || { month, expenses: 0, credits: 0 };
      if (transaction.type === "Expense") current.expenses += transaction.amount;
      if (transaction.type === "Credit") current.credits += transaction.amount;
      monthMap.set(month, current);
    });

    const months = Array.from(monthMap.values())
      .sort((a, b) => a.month.localeCompare(b.month))
      .map((month) => ({ ...month, net: month.expenses - month.credits }));

    const dates = transactions.map((transaction) => transaction.date).filter(Boolean).sort();

    return {
      totalExpenses,
      totalCredits,
      netExpense: totalExpenses - totalCredits,
      transactionCount: transactions.length,
      categories,
      months,
      periodStart: dates[0] || "",
      periodEnd: dates[dates.length - 1] || ""
    };
  }, [activeCategories, data]);

  const categoryStats = useMemo(
    () => Object.fromEntries(report.categories.map((category) => [category.id, category])),
    [report.categories]
  );

  const totalCategoryBudget = activeCategories.reduce((sum, category) => sum + category.budget, 0);
  const totalShareAmount = (data?.shareholders || []).reduce((sum, shareholder) => sum + shareholder.amount, 0);
  const budgetRemaining = totalCategoryBudget - report.totalExpenses;
  const overallCategoryCompletion = activeCategories.length
    ? Math.round(activeCategories.reduce((sum, category) => sum + category.completion, 0) / activeCategories.length)
    : 0;

  const completedWorks = data?.works.filter((work) => work.isCompleted).length || 0;
  const overdueWorks = data?.works.filter((work) => workStatus(work) === "Overdue").length || 0;
  const openingDate = parseLocalDate(data?.project.openingDate);
  const openingDays = openingDate ? Math.max(0, daysBetween(startOfToday(), openingDate)) : 0;

  const alerts = useMemo(() => {
    if (!data) return [];
    const nextAlerts = data.works.map(workAlert).filter(Boolean);
    const opening = parseLocalDate(data.project.openingDate);
    if (opening) {
      const days = daysBetween(startOfToday(), opening);
      if (days < 0) {
        nextAlerts.unshift({
          level: "danger",
          title: "Opening date has passed",
          detail: "Delvin can update the opening date in Project settings."
        });
      } else if (days <= 14) {
        nextAlerts.unshift({
          level: "warning",
          title: "Opening day is getting close",
          detail: `${days} day${days === 1 ? "" : "s"} remaining`
        });
      }
    }
    return nextAlerts;
  }, [data]);

  const visibleWorks = useMemo(() => {
    const works = data?.works || [];
    return works
      .filter((work) => activeCategory === "all" || work.categoryId === activeCategory)
      .filter((work) => {
        if (workStatusFilter === "all") return true;
        return workStatus(work).toLowerCase() === workStatusFilter;
      })
      .slice()
      .sort((a, b) => String(b.workDate).localeCompare(String(a.workDate)) || a.sortOrder - b.sortOrder);
  }, [activeCategory, data, workStatusFilter]);

  const filteredTransactions = useMemo(() => {
    const search = transactionFilters.search.trim().toLowerCase();
    return (data?.transactions || []).filter((transaction) => {
      if (transactionFilters.from && transaction.date < transactionFilters.from) return false;
      if (transactionFilters.to && transaction.date > transactionFilters.to) return false;
      if (transactionFilters.type !== "all" && transaction.type !== transactionFilters.type) return false;
      if (transactionFilters.category !== "all" && transaction.categoryId !== transactionFilters.category) return false;
      if (search) {
        const haystack = `${transaction.description} ${transaction.notes} ${categoryById[transaction.categoryId]?.name || ""}`.toLowerCase();
        if (!haystack.includes(search)) return false;
      }
      return true;
    });
  }, [categoryById, data, transactionFilters]);

  const totalTransactionPages = Math.max(1, Math.ceil(filteredTransactions.length / PAGE_SIZE));
  const pagedTransactions = filteredTransactions.slice(
    (transactionPage - 1) * PAGE_SIZE,
    transactionPage * PAGE_SIZE
  );

  useEffect(() => {
    setTransactionPage(1);
  }, [transactionFilters]);

  useEffect(() => {
    if (transactionPage > totalTransactionPages) setTransactionPage(totalTransactionPages);
  }, [transactionPage, totalTransactionPages]);

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
    setIsLoggedIn(true);
  }

  async function logout() {
    const token = currentUser?.token;
    window.sessionStorage.removeItem(USER_SESSION_KEY);
    setData(null);
    setCurrentUser(null);
    setIsLoggedIn(false);
    setModal("");
    setShowAlerts(false);

    if (token) {
      await supabase.rpc("mecardee_logout", { p_session_token: token });
    }
  }

  async function addNewUser(event) {
    event.preventDefault();
    if (!isAdmin) return;

    // MECARDEE_ASYNC_FORM_RESET_HOTFIX_V1
    const formElement = event.currentTarget;
    const form = new FormData(formElement);
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

    formElement?.reset();
    setAccountMessage(String(message || "Read-only user created successfully."));
  }

  async function changeCurrentPassword(event) {
    event.preventDefault();
    const formElement = event.currentTarget;
    const form = new FormData(formElement);
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

    formElement?.reset();
    setAccountMessage(String(message || "Password changed successfully."));
  }

  async function adminRpc(functionName, args, successMessage) {
    if (!isAdmin) {
      notify("This account has view-only access.");
      return { ok: false, data: null };
    }

    setIsSyncing(true);
    const { data: result, error } = await supabase.rpc(functionName, {
      p_session_token: currentUser.token,
      ...args
    });
    setIsSyncing(false);

    if (error) {
      notify(error.message || "Could not save the change.");
      return { ok: false, data: null };
    }

    await loadData({ quiet: true });
    if (successMessage) notify(successMessage);
    return { ok: true, data: result };
  }

  async function saveProject(event) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const result = await adminRpc("mecardee_admin_save_project", {
      p_name: String(form.get("name") || ""),
      p_location: String(form.get("location") || ""),
      p_opening_date: String(form.get("openingDate") || "")
    }, "Project settings saved.");

    if (result.ok) setModal("");
  }

  async function saveCategory(event, category = null) {
    event.preventDefault();
    const formElement = event.currentTarget;
    const form = new FormData(formElement);
    const result = await adminRpc("mecardee_admin_save_category", {
      p_id: category?.id || null,
      p_name: String(form.get("name") || ""),
      p_icon: String(form.get("icon") || "•"),
      p_budget: Number(form.get("budget") || 0),
      p_completion: Number(form.get("completion") || 0),
      p_sort_order: Number(form.get("sortOrder") || 0),
      p_is_active: form.get("isActive") === "on"
    }, category ? `${category.name} updated.` : "Category added.");

    if (result.ok && !category) formElement?.reset();
  }

  async function saveShareholder(event, shareholder = null) {
    event.preventDefault();
    const formElement = event.currentTarget;
    const form = new FormData(formElement);
    const result = await adminRpc("mecardee_admin_save_shareholder", {
      p_id: shareholder?.id || null,
      p_name: String(form.get("name") || ""),
      p_amount: Number(form.get("amount") || 0),
      p_sort_order: Number(form.get("sortOrder") || 0)
    }, shareholder ? `${shareholder.name} share updated.` : "Shareholder added.");

    if (result.ok && !shareholder) formElement?.reset();
  }

  function openNewWork() {
    setWorkDraft(emptyWork(activeCategories));
    setModal("works");
  }

  function openEditWork(work) {
    setWorkDraft({ ...work });
    setModal("works");
  }

  async function saveWork(event) {
    event.preventDefault();
    if (!workDraft) return;

    const result = await adminRpc("mecardee_admin_save_work", {
      p_id: workDraft.id || null,
      p_title: workDraft.title,
      p_category_id: workDraft.categoryId,
      p_owner: workDraft.owner,
      p_work_date: workDraft.workDate,
      p_deadline: workDraft.deadline,
      p_is_completed: Boolean(workDraft.isCompleted),
      p_entry_type: workDraft.entryType,
      p_amount: Number(workDraft.amount || 0),
      p_notes: workDraft.notes,
      p_sort_order: Number(workDraft.sortOrder || 0)
    }, workDraft.id ? "Work updated." : "Today’s work added.");

    if (result.ok) setWorkDraft(emptyWork(activeCategories));
  }

  async function deleteWork(work) {
    if (!isAdmin || !window.confirm(`Delete "${work.title}"?`)) return;
    const result = await adminRpc("mecardee_admin_delete_work", {
      p_id: work.id
    }, "Work deleted.");

    if (result.ok && workDraft?.id === work.id) {
      setWorkDraft(emptyWork(activeCategories));
    }
  }

  async function toggleWorkCompleted(work) {
    await adminRpc("mecardee_admin_save_work", {
      p_id: work.id,
      p_title: work.title,
      p_category_id: work.categoryId,
      p_owner: work.owner,
      p_work_date: work.workDate,
      p_deadline: work.deadline,
      p_is_completed: !work.isCompleted,
      p_entry_type: work.entryType,
      p_amount: work.amount,
      p_notes: work.notes,
      p_sort_order: work.sortOrder
    }, work.isCompleted ? "Work reopened." : "Work marked complete.");
  }

  function resetTransactionFilters() {
    setTransactionFilters({ from: "", to: "", type: "all", category: "all", search: "" });
  }

  function exportPdf() {
    if (!data) return;
    setIsExporting(true);

    try {
      const categoryRows = report.categories.map((category) => [
        category.name,
        { text: formatPlainMoney(category.spent), alignment: "right" },
        { text: `${category.share.toFixed(1)}%`, alignment: "right" },
        { text: `${category.completion}%`, alignment: "right" }
      ]);

      const monthlyRows = report.months.map((month) => [
        formatMonth(month.month),
        { text: formatPlainMoney(month.expenses), alignment: "right" },
        { text: formatPlainMoney(month.credits), alignment: "right" },
        { text: formatPlainMoney(month.net), alignment: "right" }
      ]);

      const transactionRows = data.transactions.map((transaction, index) => [
        index + 1,
        formatDate(transaction.date),
        transaction.date.slice(0, 7),
        transaction.type,
        transaction.description,
        transaction.type === "Credit" ? "Credit Received" : categoryById[transaction.categoryId]?.name || "Uncategorised",
        { text: formatPlainMoney(transaction.amount), alignment: "right" },
        {
          text: `${transaction.type === "Credit" ? "" : "-"}${formatPlainMoney(transaction.amount)}`,
          alignment: "right"
        }
      ]);

      const doc = {
        pageSize: "A4",
        pageOrientation: "landscape",
        pageMargins: [28, 34, 28, 34],
        content: [
          { text: "PALA WORKSHOP / SITE - FINAL FINANCIAL REPORT", style: "title" },
          {
            text: `Reporting period: ${formatDate(report.periodStart)} to ${formatDate(report.periodEnd)} | Finalized from ${report.transactionCount} reviewed transactions`,
            style: "subtitle",
            margin: [0, 3, 0, 18]
          },
          {
            columns: [
              { stack: [{ text: "TOTAL EXPENSES", style: "kpiLabel" }, { text: formatMoney(report.totalExpenses), style: "kpiValue" }] },
              { stack: [{ text: "TOTAL CREDITS", style: "kpiLabel" }, { text: formatMoney(report.totalCredits), style: "kpiValue" }] },
              { stack: [{ text: "NET EXPENSE", style: "kpiLabel" }, { text: formatMoney(report.netExpense), style: "kpiValue" }] },
              { stack: [{ text: "TRANSACTIONS", style: "kpiLabel" }, { text: String(report.transactionCount), style: "kpiValue" }] }
            ],
            columnGap: 12,
            margin: [0, 0, 0, 22]
          },
          {
            columns: [
              {
                width: "*",
                stack: [
                  { text: "EXPENSES BY CATEGORY", style: "sectionTitle" },
                  {
                    table: {
                      headerRows: 1,
                      widths: ["*", 88, 70, 70],
                      body: [
                        ["Category", "Amount (₹)", "% of Expenses", "Completion"],
                        ...categoryRows
                      ]
                    },
                    layout: "lightHorizontalLines"
                  }
                ]
              },
              {
                width: "*",
                stack: [
                  { text: "MONTHLY CASH FLOW SUMMARY", style: "sectionTitle" },
                  {
                    table: {
                      headerRows: 1,
                      widths: ["*", 88, 88, 88],
                      body: [
                        ["Month", "Expenses (₹)", "Credits (₹)", "Net Expense (₹)"],
                        ...monthlyRows
                      ]
                    },
                    layout: "lightHorizontalLines"
                  }
                ]
              }
            ],
            columnGap: 20
          },
          { text: "TRANSACTION REGISTER", style: "sectionTitle", pageBreak: "before" },
          {
            table: {
              headerRows: 1,
              widths: [28, 58, 48, 42, 130, 105, 62, 68],
              body: [
                ["Sl.", "Date", "Month", "Type", "Description", "Category", "Amount (₹)", "Net Effect (₹)"],
                ...transactionRows
              ]
            },
            layout: "lightHorizontalLines",
            fontSize: 7
          }
        ],
        styles: {
          title: { fontSize: 19, bold: true, color: "#071a17" },
          subtitle: { fontSize: 8, color: "#64736f" },
          kpiLabel: { fontSize: 8, bold: true, color: "#64736f" },
          kpiValue: { fontSize: 19, bold: true, color: "#10201d", margin: [0, 4, 0, 0] },
          sectionTitle: { fontSize: 11, bold: true, color: "#071a17", margin: [0, 0, 0, 8] }
        },
        defaultStyle: { font: "Roboto", fontSize: 8, color: "#10201d" },
        footer(currentPage, pageCount) {
          return {
            text: `${data.project.name} · Page ${currentPage} of ${pageCount}`,
            alignment: "center",
            fontSize: 7,
            color: "#64736f",
            margin: [0, 8, 0, 0]
          };
        }
      };

      pdfMake.createPdf(doc).download(`mecardee-financial-report-${toDateInput()}.pdf`);
      notify("Financial report downloaded.");
    } catch (error) {
      console.error("PDF export failed:", error);
      notify("Could not generate the PDF report.");
    } finally {
      setIsExporting(false);
    }
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
          <p>Sign in to view construction, categories, financial reports and budgets.</p>
          <form onSubmit={handleLogin} className="login-form">
            <label>Username
              <input name="username" autoComplete="username" autoFocus required />
            </label>
            <label>Password
              <input name="password" type="password" autoComplete="current-password" required />
            </label>
            {loginError && <div className="login-error">{loginError}</div>}
            <button className="primary-button" type="submit" disabled={accountBusy}>
              {accountBusy ? "Signing in…" : "Sign in"}
            </button>
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
            <strong>Database upgrade required</strong>
            <p>{loadError}</p>
            <button className="primary-button" onClick={() => loadData()}>Retry connection</button>
          </div>
        ) : (
          <p>Connecting to Mecardee…</p>
        )}
      </main>
    );
  }

  return (
    <main className="app-shell">
      <header className="topbar">
        <a className="brand" href="#top" aria-label="Mecardee home">
          <span className="brand-mark logo-image"><img src="/mecardee-logo.png" alt="Mecardee Car Wash logo" /></span>
          <span>
            <strong>{data.project.name}</strong>
            <small>{isAdmin ? "Administrator dashboard" : "View-only dashboard"}</small>
          </span>
        </a>

        <div className="top-actions">
          <span className={`sync-pill ${isSyncing ? "syncing" : ""}`}><i />{isSyncing ? "Saving" : "Live"}</span>
          <button className="notification-button" type="button" onClick={() => setShowAlerts((value) => !value)} aria-label="Open alerts">
            <span>♢</span>
            {alerts.length > 0 && <b>{alerts.length}</b>}
          </button>
          <button className="export-button" type="button" onClick={exportPdf} disabled={isExporting}>
            {isExporting ? "Generating…" : "↓ Export PDF"}
          </button>
          <button
            className="settings-button"
            type="button"
            onClick={() => {
              setAccountMessage("");
              setModal("account");
            }}
            aria-label="User settings"
            title="User settings"
          >
            <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
              <path d="M12 15.25A3.25 3.25 0 1 0 12 8.75a3.25 3.25 0 0 0 0 6.5Z" />
              <path d="M19.1 13.2a7.8 7.8 0 0 0 .05-1.2 7.8 7.8 0 0 0-.05-1.2l2-1.55-2-3.46-2.48 1a8.38 8.38 0 0 0-2.07-1.2L14.2 3h-4.4l-.35 2.59c-.74.29-1.43.69-2.07 1.2l-2.48-1-2 3.46 2 1.55a7.8 7.8 0 0 0-.05 1.2c0 .4.02.8.05 1.2l-2 1.55 2 3.46 2.48-1c.64.51 1.33.91 2.07 1.2L9.8 21h4.4l.35-2.59a8.38 8.38 0 0 0 2.07-1.2l2.48 1 2-3.46-2-1.55Z" />
            </svg>
          </button>
          <button className="secondary-button logout-button" type="button" onClick={logout}>Log out</button>
          {isAdmin && <button className="primary-button" type="button" onClick={openNewWork}>＋ Add work</button>}
        </div>

        {showAlerts && (
          <aside className="alerts-popover">
            <div className="popover-head">
              <div>
                <span className="eyebrow">Deadline centre</span>
                <h3>{alerts.length ? `${alerts.length} alert${alerts.length === 1 ? "" : "s"}` : "Everything is on track"}</h3>
              </div>
              <button className="icon-button" type="button" onClick={() => setShowAlerts(false)}>×</button>
            </div>
            <div className="alert-list">
              {alerts.length === 0 ? (
                <div className="empty-state compact">
                  <span>✓</span>
                  <p>No overdue or near-deadline work.</p>
                </div>
              ) : alerts.map((alert, index) => (
                <div className={`alert-row ${alert.level}`} key={`${alert.title}-${index}`}>
                  <i />
                  <div><strong>{alert.title}</strong><span>{alert.detail}</span></div>
                </div>
              ))}
            </div>
          </aside>
        )}
      </header>

      <section className="hero category-hero" id="top">
        <div className="hero-copy">
          <span className="location-pill">⌖ {data.project.location}</span>
          <p className="eyebrow light">CATEGORY & FINANCE CONTROL</p>
          <h1>Every rupee and<br />every work item.</h1>
          <p className="hero-subtitle">
            Track category budgets, shareholder contributions, daily work and the complete financial register in one shared dashboard.
          </p>
          <div className="hero-actions">
            {isAdmin && <button className="light-button" type="button" onClick={openNewWork}>Add today’s work</button>}
            <button className="ghost-button" type="button" onClick={() => document.getElementById("transactions")?.scrollIntoView({ behavior: "smooth" })}>
              View transaction register ↓
            </button>
          </div>
          {!isAdmin && <div className="view-only-banner">View-only account · You can filter reports and change your password.</div>}
        </div>

        <div className="hero-status category-hero-status">
          <CompletionDonut value={overallCategoryCompletion} />
          <div className="opening-meta">
            <span>Target opening</span>
            <strong>{formatDate(data.project.openingDate, { day: "numeric", month: "long", year: "numeric" })}</strong>
            <small>{openingDays} days remaining · {activeCategories.length} categories</small>
          </div>
        </div>
      </section>

      <section className="summary-grid" aria-label="Project summary">
        <article className="summary-card emphasized">
          <span className="summary-icon">₹</span>
          <div><small>Total expenses</small><strong className="money-summary">{formatMoney(report.totalExpenses)}</strong></div>
          <p>{report.transactionCount} reviewed transactions</p>
        </article>
        <article className="summary-card">
          <span className="summary-icon">＋</span>
          <div><small>Total credits</small><strong className="money-summary">{formatMoney(report.totalCredits)}</strong></div>
          <p>Recorded capital received</p>
        </article>
        <article className="summary-card">
          <span className="summary-icon">−</span>
          <div><small>Net expense</small><strong className="money-summary">{formatMoney(report.netExpense)}</strong></div>
          <p>Expenses minus credits</p>
        </article>
        <article className={`summary-card ${overdueWorks ? "danger-card" : ""}`}>
          <span className="summary-icon">✓</span>
          <div><small>Works completed</small><strong>{completedWorks}<em>/{data.works.length}</em></strong></div>
          <p>{overdueWorks ? `${overdueWorks} overdue` : "No delayed work"}</p>
        </article>
      </section>

      <section className="section-block budget-section" id="budget">
        <div className="section-heading">
          <div>
            <span className="eyebrow">Money control</span>
            <h2>Category budgets & shares</h2>
          </div>
          {isAdmin && (
            <div className="admin-action-row">
              <button className="text-button" type="button" onClick={() => setModal("categories")}>Edit categories</button>
              <button className="text-button" type="button" onClick={() => setModal("shares")}>Edit shares</button>
              <button className="text-button" type="button" onClick={() => {
                setWorkDraft(emptyWork(activeCategories));
                setModal("works");
              }}>Edit works</button>
              <button className="text-button" type="button" onClick={() => setModal("project")}>Project settings</button>
            </div>
          )}
        </div>

        <div className="budget-summary-grid">
          <article className="budget-summary-card primary-budget">
            <small>Total category budget</small>
            <strong>{formatMoney(totalCategoryBudget)}</strong>
          </article>
          <article className="budget-summary-card">
            <small>Actual amount spent</small>
            <strong>{formatMoney(report.totalExpenses)}</strong>
          </article>
          <article className={`budget-summary-card ${budgetRemaining < 0 ? "over-budget" : ""}`}>
            <small>Budget remaining</small>
            <strong>{formatMoney(budgetRemaining)}</strong>
          </article>
          <article className="budget-summary-card">
            <small>Total shareholder shares</small>
            <strong>{formatMoney(totalShareAmount)}</strong>
          </article>
        </div>

        <div className="shareholder-heading">
          <div>
            <span className="eyebrow">Capital contributors</span>
            <h3>Shareholders</h3>
          </div>
          <small>Initial amounts are taken from the workbook credit register.</small>
        </div>

        <div className="shareholder-grid">
          {data.shareholders.map((shareholder, index) => (
            <article className="shareholder-card" key={shareholder.id}>
              <span className="share-index">{pad(index + 1)}</span>
              <div className="share-avatar">{shareholder.name.slice(0, 1).toUpperCase()}</div>
              <div>
                <small>Shareholder</small>
                <strong>{shareholder.name}</strong>
                <p>{formatMoney(shareholder.amount)}</p>
              </div>
            </article>
          ))}
        </div>

        <div className="category-budget-grid">
          {activeCategories.map((category) => {
            const stat = categoryStats[category.id] || { spent: 0, available: category.budget };
            return (
              <article className="category-budget-card" key={category.id}>
                <div className="category-budget-head">
                  <span className="phase-icon small-phase-icon">{category.icon}</span>
                  <div><strong>{category.name}</strong><small>{category.completion}% complete</small></div>
                </div>
                <dl>
                  <div><dt>Budget</dt><dd>{formatMoney(category.budget)}</dd></div>
                  <div><dt>Spent</dt><dd>{formatMoney(stat.spent)}</dd></div>
                  <div className={stat.available < 0 ? "negative-budget" : ""}><dt>Available</dt><dd>{formatMoney(stat.available)}</dd></div>
                </dl>
                <div className="mini-progress"><i style={{ width: `${category.completion}%` }} /></div>
              </article>
            );
          })}
        </div>
      </section>

      <section className="section-block category-health-section">
        <div className="section-heading">
          <div>
            <span className="eyebrow">Main category readiness</span>
            <h2>Category completion</h2>
          </div>
          <span className="section-note">Individual works no longer use percentage sliders.</span>
        </div>

        <div className="category-health-layout">
          <article className="category-kpi-panel">
            <CompletionDonut value={overallCategoryCompletion} label="average completion" size={190} />
            <div>
              <small>Across active categories</small>
              <strong>{overallCategoryCompletion}%</strong>
              <p>Completion is maintained only at category level by Delvin.</p>
            </div>
          </article>

          <div className="category-progress-list">
            {activeCategories.map((category) => (
              <article key={category.id}>
                <div>
                  <span className="phase-icon small-phase-icon">{category.icon}</span>
                  <div><strong>{category.name}</strong><small>{categoryStats[category.id]?.spent ? `${formatMoney(categoryStats[category.id].spent)} spent` : "No expense recorded"}</small></div>
                </div>
                <div className="category-completion-control">
                  <span>{category.completion}%</span>
                  <div className="category-progress-track"><i style={{ width: `${category.completion}%` }} /></div>
                  {isAdmin && <button type="button" onClick={() => setModal("categories")}>Update category</button>}
                </div>
              </article>
            ))}
          </div>
        </div>
      </section>

      <section className="section-block works-section" id="works">
        <div className="section-heading work-heading">
          <div>
            <span className="eyebrow">Daily work register</span>
            <h2>Today’s work & site activity</h2>
          </div>
          {isAdmin && <button className="primary-button" type="button" onClick={openNewWork}>＋ Add work</button>}
        </div>

        <div className="work-filter-panel">
          <select value={activeCategory} onChange={(event) => setActiveCategory(event.target.value)} aria-label="Filter works by category">
            <option value="all">All categories</option>
            {activeCategories.map((category) => <option value={category.id} key={category.id}>{category.name}</option>)}
          </select>
          <select value={workStatusFilter} onChange={(event) => setWorkStatusFilter(event.target.value)} aria-label="Filter works by status">
            <option value="all">All statuses</option>
            <option value="open">Open</option>
            <option value="completed">Completed</option>
            <option value="overdue">Overdue</option>
          </select>
          <span>{visibleWorks.length} work item{visibleWorks.length === 1 ? "" : "s"}</span>
        </div>

        <div className="work-list">
          {visibleWorks.length === 0 ? (
            <div className="empty-state">
              <span>＋</span>
              <h3>No work matches this filter</h3>
              <p>{isAdmin ? "Add the next site activity or reset the filters." : "Try another category or status."}</p>
              {isAdmin && <button className="primary-button" type="button" onClick={openNewWork}>Add work</button>}
            </div>
          ) : visibleWorks.map((work) => {
            const category = categoryById[work.categoryId];
            const status = workStatus(work);
            return (
              <article className="work-card" key={work.id}>
                <div className={`status-dot ${status.toLowerCase()}`} />
                <div className="work-card-copy">
                  <div className="task-meta">
                    <span>{category?.icon || "•"} {category?.name || "Uncategorised"}</span>
                    <span className={`status-badge ${status.toLowerCase()}`}>{status}</span>
                    {work.entryType !== "Work" && <span className={`report-entry-badge ${work.entryType.toLowerCase()}`}>{work.entryType} entry</span>}
                  </div>
                  <h3>{work.title}</h3>
                  {work.notes && <p>{work.notes}</p>}
                  <div className="work-details">
                    <span>▣ Work date: {formatDate(work.workDate)}</span>
                    <span>◷ Deadline: {formatDate(work.deadline)}</span>
                    <span>👤 {work.owner || "Not assigned"}</span>
                    {work.entryType !== "Work" && <span>₹ {formatMoney(work.amount)}</span>}
                  </div>
                </div>
                {isAdmin && (
                  <div className="work-card-actions">
                    <button className="small-button" type="button" onClick={() => toggleWorkCompleted(work)}>
                      {work.isCompleted ? "Reopen" : "Mark complete"}
                    </button>
                    <button className="secondary-task-button" type="button" onClick={() => openEditWork(work)}>Edit</button>
                    <button className="delete-button" type="button" onClick={() => deleteWork(work)}>Delete</button>
                  </div>
                )}
              </article>
            );
          })}
        </div>
      </section>

      <section className="section-block financial-report-section" id="report">
        <div className="report-document">
          <div className="report-title-row">
            <div>
              <span className="eyebrow">Workbook sheet 1</span>
              <h2>PALA WORKSHOP / SITE - FINAL FINANCIAL REPORT</h2>
              <p>
                Reporting period: {formatDate(report.periodStart)} to {formatDate(report.periodEnd)} · Finalized from {report.transactionCount} reviewed transactions
              </p>
            </div>
            <button className="secondary-button report-download-button" type="button" onClick={exportPdf}>Download PDF</button>
          </div>

          <div className="report-kpi-grid">
            <article><small>TOTAL EXPENSES</small><strong>{formatMoney(report.totalExpenses)}</strong></article>
            <article><small>TOTAL CREDITS</small><strong>{formatMoney(report.totalCredits)}</strong></article>
            <article><small>NET EXPENSE</small><strong>{formatMoney(report.netExpense)}</strong></article>
            <article><small>TRANSACTIONS</small><strong>{report.transactionCount}</strong></article>
          </div>

          <div className="report-table-layout">
            <article className="report-table-card">
              <h3>EXPENSES BY CATEGORY</h3>
              <div className="responsive-table">
                <table>
                  <thead><tr><th>Category</th><th>Amount (₹)</th><th>% of Expenses</th></tr></thead>
                  <tbody>
                    {report.categories.map((category) => (
                      <tr key={category.id}>
                        <td>{category.name}</td>
                        <td>{formatPlainMoney(category.spent)}</td>
                        <td>{category.share.toFixed(2)}%</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </article>

            <article className="report-table-card">
              <h3>MONTHLY CASH FLOW SUMMARY</h3>
              <div className="responsive-table">
                <table>
                  <thead><tr><th>Month</th><th>Expenses (₹)</th><th>Credits (₹)</th><th>Net Expense (₹)</th></tr></thead>
                  <tbody>
                    {report.months.map((month) => (
                      <tr key={month.month}>
                        <td>{formatMonth(month.month)}</td>
                        <td>{formatPlainMoney(month.expenses)}</td>
                        <td>{formatPlainMoney(month.credits)}</td>
                        <td className={month.net < 0 ? "positive-net" : ""}>{formatPlainMoney(month.net)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </article>
          </div>

          <div className="report-basis">
            <strong>REPORT BASIS</strong>
            <p>
              All corrected entries from the reviewed workbook are included. Circled amounts and amounts written beside “വരവ്” are treated as credits. Crossed-out amounts are excluded. Net Expense = Total Expenses - Total Credits.
            </p>
          </div>
        </div>
      </section>

      <section className="section-block transaction-section" id="transactions">
        <div className="report-document transaction-document">
          <div className="report-title-row">
            <div>
              <span className="eyebrow">Workbook sheet 2</span>
              <h2>Final Transaction Register</h2>
              <p>Sorted by date · Reporting period: {formatDate(report.periodStart)} to {formatDate(report.periodEnd)}</p>
            </div>
            <span className="transaction-count-pill">{filteredTransactions.length} records</span>
          </div>

          <div className="transaction-filter-grid">
            <label>From date
              <input type="date" value={transactionFilters.from} onChange={(event) => setTransactionFilters({ ...transactionFilters, from: event.target.value })} />
            </label>
            <label>To date
              <input type="date" value={transactionFilters.to} onChange={(event) => setTransactionFilters({ ...transactionFilters, to: event.target.value })} />
            </label>
            <label>Type
              <select value={transactionFilters.type} onChange={(event) => setTransactionFilters({ ...transactionFilters, type: event.target.value })}>
                <option value="all">All types</option>
                <option value="Expense">Expense</option>
                <option value="Credit">Credit</option>
              </select>
            </label>
            <label>Category
              <select value={transactionFilters.category} onChange={(event) => setTransactionFilters({ ...transactionFilters, category: event.target.value })}>
                <option value="all">All categories</option>
                {activeCategories.map((category) => <option value={category.id} key={category.id}>{category.name}</option>)}
              </select>
            </label>
            <label className="search-filter">Search
              <input
                value={transactionFilters.search}
                onChange={(event) => setTransactionFilters({ ...transactionFilters, search: event.target.value })}
                placeholder="Description or notes"
              />
            </label>
            <button className="secondary-button reset-filter-button" type="button" onClick={resetTransactionFilters}>Reset filters</button>
          </div>

          <div className="responsive-table transaction-table-wrap">
            <table className="transaction-table">
              <thead>
                <tr>
                  <th>Sl. No.</th>
                  <th>Date</th>
                  <th>Month</th>
                  <th>Type</th>
                  <th>Description</th>
                  <th>Category</th>
                  <th>Amount (₹)</th>
                  <th>Net Effect (₹)</th>
                </tr>
              </thead>
              <tbody>
                {pagedTransactions.map((transaction) => {
                  const originalIndex = data.transactions.findIndex((item) => item.id === transaction.id);
                  return (
                    <tr key={transaction.id}>
                      <td>{originalIndex + 1}</td>
                      <td>{formatDate(transaction.date)}</td>
                      <td>{transaction.date.slice(0, 7)}</td>
                      <td><span className={`transaction-type ${transaction.type.toLowerCase()}`}>{transaction.type}</span></td>
                      <td>{transaction.description}</td>
                      <td>{transaction.type === "Credit" ? "Credit Received" : categoryById[transaction.categoryId]?.name || "Uncategorised"}</td>
                      <td>{formatPlainMoney(transaction.amount)}</td>
                      <td className={transaction.type === "Credit" ? "credit-effect" : "expense-effect"}>
                        {transaction.type === "Credit" ? "+" : "-"}{formatPlainMoney(transaction.amount)}
                      </td>
                    </tr>
                  );
                })}
                {pagedTransactions.length === 0 && (
                  <tr><td colSpan="8" className="empty-table-row">No transactions match the selected filters.</td></tr>
                )}
              </tbody>
            </table>
          </div>

          <div className="pagination-row">
            <span>Page {transactionPage} of {totalTransactionPages}</span>
            <div>
              <button className="secondary-button" type="button" disabled={transactionPage === 1} onClick={() => setTransactionPage((page) => Math.max(1, page - 1))}>Previous</button>
              <button className="secondary-button" type="button" disabled={transactionPage === totalTransactionPages} onClick={() => setTransactionPage((page) => Math.min(totalTransactionPages, page + 1))}>Next</button>
            </div>
          </div>
        </div>
      </section>

      <nav className="mobile-nav" aria-label="Mobile navigation">
        <a href="#top"><span>⌂</span><small>Home</small></a>
        <a href="#budget"><span>₹</span><small>Budget</small></a>
        <a href="#works"><span>✓</span><small>Works</small></a>
        <a href="#report"><span>▤</span><small>Report</small></a>
        <a href="#transactions"><span>≡</span><small>Register</small></a>
      </nav>

      <footer>
        <div className="brand footer-brand">
          <span className="brand-mark logo-image"><img src="/mecardee-logo.png" alt="Mecardee Car Wash logo" /></span>
          <span><strong>Mecardee Car Wash</strong><small>Category & financial control</small></span>
        </div>
        <p>Connected to Supabase. Delvin has edit access; additional users are view-only.</p>
      </footer>

      {modal === "account" && (
        <Modal title="User settings" onClose={() => setModal("")}>
          <div className="user-settings-panel">
            <div className="current-user-card">
              <div className="user-avatar">{String(currentUser?.username || "U").slice(0, 1).toUpperCase()}</div>
              <div>
                <span>Signed in as</span>
                <strong>{currentUser?.username}</strong>
                <small>{isAdmin ? "Administrator · Full permissions" : "Viewer · Read-only permissions"}</small>
              </div>
            </div>

            {accountMessage && <div className="account-message">{accountMessage}</div>}

            <section className="account-setting-section">
              <div className="account-section-heading">
                <span>01</span>
                <div><h3>Change my password</h3><p>Update the password for {currentUser?.username}.</p></div>
              </div>
              <form className="account-form" onSubmit={changeCurrentPassword}>
                <label>Current password<input name="currentPassword" type="password" autoComplete="current-password" required /></label>
                <label>New password<input name="changedPassword" type="password" minLength="4" autoComplete="new-password" required /></label>
                <label>Confirm new password<input name="confirmChangedPassword" type="password" minLength="4" autoComplete="new-password" required /></label>
                <button className="primary-button" type="submit" disabled={accountBusy}>{accountBusy ? "Saving…" : "Change password"}</button>
                <button className="secondary-button logout-button" type="button" onClick={logout}>Log out</button>
              </form>
            </section>

            {isAdmin && (
              <section className="account-setting-section admin-user-section">
                <div className="account-section-heading">
                  <span>02</span>
                  <div>
                    <h3>Add a new viewer</h3>
                    <p>New users can view and filter everything, export reports and change only their own password.</p>
                  </div>
                </div>
                <form className="account-form" onSubmit={addNewUser}>
                  <label>Username<input name="newUsername" minLength="3" pattern="[a-zA-Z0-9._-]+" autoComplete="off" required /></label>
                  <label>Password<input name="newPassword" type="password" minLength="4" autoComplete="new-password" required /></label>
                  <label>Confirm password<input name="confirmNewPassword" type="password" minLength="4" autoComplete="new-password" required /></label>
                  <button className="primary-button" type="submit" disabled={accountBusy}>{accountBusy ? "Creating…" : "Add viewer"}</button>
                </form>
              </section>
            )}
          </div>
        </Modal>
      )}

      {modal === "project" && isAdmin && (
        <Modal title="Project settings" onClose={() => setModal("")}>
          <form className="form-grid" onSubmit={saveProject}>
            <label className="full-field">Business name<input name="name" defaultValue={data.project.name} required /></label>
            <label>Location<input name="location" defaultValue={data.project.location} /></label>
            <label>Target opening date<input name="openingDate" type="date" defaultValue={data.project.openingDate} required /></label>
            <div className="frontend-note full-field">Budgets are edited only inside categories. All changes require Delvin’s admin session.</div>
            <div className="modal-actions full-field">
              <button className="secondary-button" type="button" onClick={() => setModal("")}>Cancel</button>
              <button className="primary-button" type="submit" disabled={isSyncing}>Save settings</button>
            </div>
          </form>
        </Modal>
      )}

      {modal === "categories" && isAdmin && (
        <Modal title="Edit categories" eyebrow="Administrator controls" onClose={() => setModal("")} wide>
          <div className="editor-intro">
            <p>Budgets and completion percentages belong only to main categories. Rename, reorder, disable or update them here.</p>
          </div>

          <div className="category-editor-list">
            {data.categories.map((category) => (
              <form className="category-editor-row" onSubmit={(event) => saveCategory(event, category)} key={category.id}>
                <label>Icon<input name="icon" defaultValue={category.icon} maxLength="4" /></label>
                <label className="category-name-field">Category name<input name="name" defaultValue={category.name} required /></label>
                <label>Budget (₹)<input name="budget" type="number" min="0" step="1" defaultValue={category.budget} /></label>
                <label>Completion %
                  <input name="completion" type="number" min="0" max="100" step="1" defaultValue={category.completion} />
                </label>
                <label>Order<input name="sortOrder" type="number" step="1" defaultValue={category.sortOrder} /></label>
                <label className="checkbox-field"><input name="isActive" type="checkbox" defaultChecked={category.isActive} /> Active</label>
                <button className="small-button" type="submit" disabled={isSyncing}>Save</button>
              </form>
            ))}
          </div>

          <form className="new-editor-row" onSubmit={(event) => saveCategory(event, null)}>
            <div><span className="eyebrow">Add category</span><h3>New main category</h3></div>
            <input name="icon" placeholder="Icon" defaultValue="•" maxLength="4" />
            <input name="name" placeholder="Category name" required />
            <input name="budget" type="number" min="0" step="1" placeholder="Budget" />
            <input name="completion" type="number" min="0" max="100" step="1" placeholder="Completion %" />
            <input name="sortOrder" type="number" step="1" placeholder="Order" />
            <input name="isActive" type="hidden" value="on" />
            <button className="primary-button" type="submit" disabled={isSyncing}>Add category</button>
          </form>
        </Modal>
      )}

      {modal === "shares" && isAdmin && (
        <Modal title="Edit shareholder shares" eyebrow="Administrator controls" onClose={() => setModal("")} wide>
          <div className="editor-intro"><p>Update the amount shown for Delvin, Dennis and Dantees under the budget cards.</p></div>
          <div className="share-editor-list">
            {data.shareholders.map((shareholder) => (
              <form className="share-editor-row" onSubmit={(event) => saveShareholder(event, shareholder)} key={shareholder.id}>
                <label>Shareholder name<input name="name" defaultValue={shareholder.name} required /></label>
                <label>Share amount (₹)<input name="amount" type="number" min="0" step="1" defaultValue={shareholder.amount} /></label>
                <label>Order<input name="sortOrder" type="number" step="1" defaultValue={shareholder.sortOrder} /></label>
                <button className="small-button" type="submit" disabled={isSyncing}>Save share</button>
              </form>
            ))}
          </div>
          <form className="new-editor-row share-add-row" onSubmit={(event) => saveShareholder(event, null)}>
            <div><span className="eyebrow">Optional</span><h3>Add shareholder</h3></div>
            <input name="name" placeholder="Name" required />
            <input name="amount" type="number" min="0" step="1" placeholder="Share amount" />
            <input name="sortOrder" type="number" step="1" placeholder="Order" />
            <button className="primary-button" type="submit" disabled={isSyncing}>Add shareholder</button>
          </form>
        </Modal>
      )}

      {modal === "works" && isAdmin && workDraft && (
        <Modal title="Edit works" eyebrow="Administrator controls" onClose={() => setModal("")} wide>
          <div className="work-editor-layout">
            <form className="work-editor-form" onSubmit={saveWork}>
              <div className="work-editor-title">
                <span className="eyebrow">{workDraft.id ? "Edit selected work" : "Add today’s work"}</span>
                <h3>{workDraft.id ? workDraft.title : "New work item"}</h3>
              </div>
              <label className="full-field">Description
                <input autoFocus required value={workDraft.title} onChange={(event) => setWorkDraft({ ...workDraft, title: event.target.value })} placeholder="Work or transaction description" />
              </label>
              <label>Category
                <select required value={workDraft.categoryId} onChange={(event) => setWorkDraft({ ...workDraft, categoryId: event.target.value })}>
                  {activeCategories.map((category) => <option value={category.id} key={category.id}>{category.name}</option>)}
                </select>
              </label>
              <label>Responsible person
                <input value={workDraft.owner} onChange={(event) => setWorkDraft({ ...workDraft, owner: event.target.value })} placeholder="Owner / contractor" />
              </label>
              <label>Work date
                <input type="date" required value={workDraft.workDate} onChange={(event) => setWorkDraft({ ...workDraft, workDate: event.target.value })} />
              </label>
              <label>Deadline
                <input type="date" required value={workDraft.deadline} onChange={(event) => setWorkDraft({ ...workDraft, deadline: event.target.value })} />
              </label>
              <label>Report entry
                <select value={workDraft.entryType} onChange={(event) => setWorkDraft({ ...workDraft, entryType: event.target.value, amount: event.target.value === "Work" ? 0 : workDraft.amount })}>
                  <option value="Work">Work only · no financial entry</option>
                  <option value="Expense">Expense · include in report</option>
                  <option value="Credit">Credit · include in report</option>
                </select>
              </label>
              <label>Amount (₹)
                <input
                  type="number"
                  min="0"
                  step="1"
                  disabled={workDraft.entryType === "Work"}
                  required={workDraft.entryType !== "Work"}
                  value={workDraft.amount}
                  onChange={(event) => setWorkDraft({ ...workDraft, amount: Number(event.target.value || 0) })}
                />
              </label>
              <label>Display order
                <input type="number" step="1" value={workDraft.sortOrder} onChange={(event) => setWorkDraft({ ...workDraft, sortOrder: Number(event.target.value || 0) })} />
              </label>
              <label className="checkbox-field work-complete-field">
                <input type="checkbox" checked={workDraft.isCompleted} onChange={(event) => setWorkDraft({ ...workDraft, isCompleted: event.target.checked })} />
                Work completed
              </label>
              <label className="full-field">Notes
                <textarea value={workDraft.notes} onChange={(event) => setWorkDraft({ ...workDraft, notes: event.target.value })} placeholder="Details for the work card and report" />
              </label>
              <div className="modal-actions full-field">
                {workDraft.id && <button className="delete-button" type="button" onClick={() => deleteWork(workDraft)}>Delete</button>}
                <button className="secondary-button" type="button" onClick={() => setWorkDraft(emptyWork(activeCategories))}>Clear</button>
                <button className="primary-button" type="submit" disabled={isSyncing}>{workDraft.id ? "Save work" : "Add work"}</button>
              </div>
            </form>

            <aside className="work-manager-list">
              <div><span className="eyebrow">Existing works</span><h3>Select to edit</h3></div>
              <div className="work-manager-scroll">
                {data.works.map((work) => (
                  <button type="button" className={workDraft.id === work.id ? "selected" : ""} onClick={() => setWorkDraft({ ...work })} key={work.id}>
                    <span>{categoryById[work.categoryId]?.icon || "•"}</span>
                    <div><strong>{work.title}</strong><small>{formatDate(work.workDate)} · {workStatus(work)}</small></div>
                  </button>
                ))}
              </div>
            </aside>
          </div>
        </Modal>
      )}

      {toast && <div className="toast">{toast}</div>}
    </main>
  );
}
