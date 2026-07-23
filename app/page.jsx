"use client";

// MECARDEE_SHARE_BUDGET_CIRCLE_V1

// MECARDEE_TRANSACTION_AMOUNT_SEARCH_V1

// MECARDEE_REPOSITION_SHAREHOLDERS_BUDGET_V1

// MECARDEE_HIDE_WORKS_COMPLETED_CARD_V2

// MECARDEE_AUTO_COMPLETE_WORK_V1

// MECARDEE_PAID_BY_PARTNER_CONTRIBUTIONS_V1

// MECARDEE_CLEAR_NET_POSITION_V1

// MECARDEE_SECURE_DELETED_ENTRIES_V1

// MECARDEE_CREDIT_DESCRIPTION_CATEGORY_V1

// MECARDEE_DYNAMIC_CREDIT_SOURCE_FILTER_V1

// MECARDEE_TODAY_OPEN_WORK_SORT_V1

// MECARDEE_INLINE_TRANSACTION_EDIT_V1

import { useCallback, useEffect, useMemo, useState } from "react";
import { supabase } from "../lib/supabase";
import pdfMake from "pdfmake/build/pdfmake";
import pdfFonts from "pdfmake/build/vfs_fonts";

pdfMake.vfs = pdfFonts;

// MECARDEE_CATEGORIES_REPORTS_PERMISSIONS_V1
// MECARDEE_FILTERED_TOTALS_CREDIT_SHAREHOLDER_V1
// MECARDEE_SEPARATE_CREDIT_ENTRY_V1
// MECARDEE_FILTERED_EXPORTS_CREDIT_LABEL_V1
// MECARDEE_WORK_EDITOR_USABILITY_V2
const USER_SESSION_KEY = "mecardee-user-session";
const PAGE_SIZE = 25;
const PARTNER_NAMES = ["Delvin", "Dantees", "Dennis"];


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
    creditShareholderId: row.credit_shareholder_id || "",
    paidById: row.paid_by || "",
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
    workId: row.work_id || null,
    shareholderId: row.shareholder_id || null,
    paidById: row.paid_by || null
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
    entryType: "Expense",
    amount: 0,
    creditShareholderId: "",
    paidById: "",
    notes: "",
    sortOrder: 0
  };
}

function emptyCredit(categories) {
  return {
    ...emptyWork(categories),
    deadline: toDateInput(),
    isCompleted: true,
    entryType: "Credit"
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
  const [transactionDraft, setTransactionDraft] = useState(null);
  const [deletePassword, setDeletePassword] = useState("");
  const [deletedTransactions, setDeletedTransactions] = useState([]);
  const [deletedEntriesLoading, setDeletedEntriesLoading] = useState(false);
  const [activeCategory, setActiveCategory] = useState("all");
  const [transactionFilters, setTransactionFilters] = useState({
    from: "",
    to: "",
    type: "all",
    category: "all",
    search: ""
  });
  const [transactionSort, setTransactionSort] = useState("date-asc");
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

  const loadDeletedTransactions = useCallback(async (sessionToken) => {
    if (!sessionToken) {
      setDeletedTransactions([]);
      return;
    }

    setDeletedEntriesLoading(true);

    const { data: result, error } = await supabase.rpc(
      "mecardee_admin_list_deleted_transactions",
      { p_session_token: sessionToken }
    );

    setDeletedEntriesLoading(false);

    if (error) {
      console.error("Deleted entries report failed:", error);
      setDeletedTransactions([]);
      return;
    }

    setDeletedTransactions((Array.isArray(result) ? result : []).map((row) => ({
      id: row.id,
      originalId: row.original_transaction_id,
      sortOrder: Number(row.original_sort_order || 0),
      date: row.txn_date,
      type: row.txn_type,
      description: row.description,
      categoryId: row.category_id || "",
      categoryName: row.category_name || "",
      amount: Number(row.amount || 0),
      notes: row.notes || "",
      workId: row.work_id || null,
      shareholderId: row.shareholder_id || null,
      shareholderName: row.shareholder_name || "",
      paidById: row.paid_by || null,
      paidByName: row.paid_by_name || "",
      deletedBy: row.deleted_by_username || "delvin",
      deletedAt: row.deleted_at
    })));
  }, []);

  useEffect(() => {
    if (!isLoggedIn || !isAdmin || !currentUser?.token) {
      setDeletedTransactions([]);
      return;
    }

    loadDeletedTransactions(currentUser.token);
  }, [currentUser?.token, isAdmin, isLoggedIn, loadDeletedTransactions]);
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

  const shareholderById = useMemo(
    () => Object.fromEntries((data?.shareholders || []).map((shareholder) => [shareholder.id, shareholder])),
    [data]
  );

  const partnerShareholders = useMemo(() => {
    const byName = Object.fromEntries(
      (data?.shareholders || []).map((shareholder) => [shareholder.name.trim().toLowerCase(), shareholder])
    );

    return PARTNER_NAMES
      .map((name) => byName[name.toLowerCase()])
      .filter(Boolean);
  }, [data]);

  const delvinPartnerId = partnerShareholders.find(
    (shareholder) => shareholder.name.trim().toLowerCase() === "delvin"
  )?.id || "";

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

  const partnerContributionReport = useMemo(() => {
    const transactions = data?.transactions || [];
    const partnerByName = Object.fromEntries(
      partnerShareholders.map((partner) => [partner.name.trim().toLowerCase(), partner])
    );
    const partnerIds = new Set(partnerShareholders.map((partner) => partner.id));

    const recordedCashCredits = Object.fromEntries(
      partnerShareholders.map((partner) => [partner.id, 0])
    );
    const directExpensesPaid = Object.fromEntries(
      partnerShareholders.map((partner) => [partner.id, 0])
    );

    transactions.forEach((transaction) => {
      if (
        transaction.type === "Credit" &&
        transaction.shareholderId &&
        partnerIds.has(transaction.shareholderId)
      ) {
        recordedCashCredits[transaction.shareholderId] =
          Number(recordedCashCredits[transaction.shareholderId] || 0) + transaction.amount;
      }

      if (
        transaction.type === "Expense" &&
        transaction.paidById &&
        partnerIds.has(transaction.paidById)
      ) {
        directExpensesPaid[transaction.paidById] =
          Number(directExpensesPaid[transaction.paidById] || 0) + transaction.amount;
      }
    });

    const delvin = partnerByName.delvin;
    const dantees = partnerByName.dantees;
    const dennis = partnerByName.dennis;
    const totalRecordedPartnerCredits = Object.values(recordedCashCredits)
      .reduce((sum, amount) => sum + Number(amount || 0), 0);
    const danteesDirect = dantees ? Number(directExpensesPaid[dantees.id] || 0) : 0;
    const dennisDirect = dennis ? Number(directExpensesPaid[dennis.id] || 0) : 0;
    const rawDelvinUnrecorded =
      report.totalExpenses -
      totalRecordedPartnerCredits -
      danteesDirect -
      dennisDirect;
    const delvinUnrecorded = Math.max(0, rawDelvinUnrecorded);

    const rows = PARTNER_NAMES.map((partnerName) => {
      const partner = partnerByName[partnerName.toLowerCase()];
      const cashCredits = partner ? Number(recordedCashCredits[partner.id] || 0) : 0;
      const directExpenses = partner ? Number(directExpensesPaid[partner.id] || 0) : 0;
      const unrecorded = partnerName === "Delvin" ? delvinUnrecorded : 0;

      return {
        id: partner?.id || partnerName.toLowerCase(),
        name: partnerName,
        recordedCashCredits: cashCredits,
        directExpensesPaid: directExpenses,
        calculatedUnrecordedContribution: unrecorded,
        totalContribution: cashCredits + directExpenses + unrecorded
      };
    });

    // Delvin's total follows the requested accounting rule and must not add
    // his informational direct-expense column a second time.
    const delvinRow = rows.find((row) => row.name === "Delvin");
    if (delvinRow) {
      delvinRow.totalContribution =
        delvinRow.recordedCashCredits +
        delvinRow.calculatedUnrecordedContribution;
    }

    return {
      rows,
      totalRecordedPartnerCredits,
      rawDelvinUnrecorded,
      delvinUnrecorded,
      hasExcessRecordedCredits: rawDelvinUnrecorded < 0,
      totalContribution: rows.reduce((sum, row) => sum + row.totalContribution, 0)
    };
  }, [data, partnerShareholders, report.totalExpenses]);

  const partnerContributionById = useMemo(
    () => Object.fromEntries(
      partnerContributionReport.rows.map((row) => [row.id, row])
    ),
    [partnerContributionReport.rows]
  );

  const categoryStats = useMemo(
    () => Object.fromEntries(report.categories.map((category) => [category.id, category])),
    [report.categories]
  );

  const totalCategoryBudget = activeCategories.reduce((sum, category) => sum + category.budget, 0);
  const totalShareAmount = partnerContributionReport.totalContribution;

  const shareBudgetCircle = (() => {
    const colors = ["#0b6b58", "#d7ff4f", "#66d5c5"];
    let cursor = 0;
    const gradientParts = [];

    const rows = partnerShareholders.map((shareholder, index) => {
      const contribution = Number(
        partnerContributionById[shareholder.id]?.totalContribution || 0
      );
      const percentage = totalCategoryBudget > 0
        ? (contribution / totalCategoryBudget) * 100
        : 0;

      const availableRing = Math.max(100 - cursor, 0);
      const visiblePercentage = Math.min(
        Math.max(percentage, 0),
        availableRing
      );
      const color = colors[index % colors.length];

      if (visiblePercentage > 0) {
        gradientParts.push(
          `${color} ${cursor}% ${cursor + visiblePercentage}%`
        );
        cursor += visiblePercentage;
      }

      return {
        id: shareholder.id,
        name: shareholder.name,
        percentage,
        color
      };
    });

    if (cursor < 100) {
      gradientParts.push(`#e8efeb ${cursor}% 100%`);
    }

    return {
      rows,
      gradient: `conic-gradient(${gradientParts.join(", ")})`
    };
  })();

  const budgetRemaining = totalCategoryBudget - report.totalExpenses;
  const overallCategoryCompletion = activeCategories.length
    ? Math.round(activeCategories.reduce((sum, category) => sum + category.completion, 0) / activeCategories.length)
    : 0;

  const trackedWorks = (data?.works || []).filter((work) => work.entryType !== "Credit");
  const completedWorks = trackedWorks.filter((work) => work.isCompleted).length;
  const overdueWorks = trackedWorks.filter((work) => workStatus(work) === "Overdue").length;
  const openingDate = parseLocalDate(data?.project.openingDate);
  const openingDays = openingDate ? Math.max(0, daysBetween(startOfToday(), openingDate)) : 0;

  const alerts = useMemo(() => {
    if (!data) return [];
    const nextAlerts = data.works
      .filter((work) => work.entryType !== "Credit")
      .map(workAlert)
      .filter(Boolean);
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

  const { todayWorks, openWorks } = useMemo(() => {
    const today = toDateInput();
    const works = (data?.works || [])
      .filter((work) => work.entryType !== "Credit")
      .filter((work) => activeCategory === "all" || work.categoryId === activeCategory)
      .slice()
      .sort((a, b) => {
        const dateOrder = String(b.workDate || "").localeCompare(String(a.workDate || ""));
        if (dateOrder !== 0) return dateOrder;
        return Number(a.sortOrder || 0) - Number(b.sortOrder || 0);
      });

    return {
      todayWorks: works.filter((work) => work.workDate === today),
      openWorks: works.filter((work) => !work.isCompleted)
    };
  }, [activeCategory, data]);

  const editableWorks = useMemo(
    () => (data?.works || [])
      .filter((work) => work.entryType !== "Credit")
      .slice()
      .sort((a, b) => {
        const completionOrder = Number(Boolean(a.isCompleted)) - Number(Boolean(b.isCompleted));
        if (completionOrder !== 0) return completionOrder;

        const dateOrder = String(b.workDate || "").localeCompare(String(a.workDate || ""));
        if (dateOrder !== 0) return dateOrder;

        return String(a.title || "").localeCompare(String(b.title || ""));
      }),
    [data]
  );

  const filteredTransactions = useMemo(() => {
    const search = transactionFilters.search.trim().toLowerCase();
    const filtered = (data?.transactions || []).filter((transaction) => {
      if (transactionFilters.from && transaction.date < transactionFilters.from) return false;
      if (transactionFilters.to && transaction.date > transactionFilters.to) return false;
      if (transactionFilters.type !== "all" && transaction.type !== transactionFilters.type) return false;
      if (transactionFilters.category !== "all") {
        if (transactionFilters.category.startsWith("credit:")) {
          if (transaction.type !== "Credit") return false;

          const selectedCreditSource = transactionFilters.category.slice("credit:".length);

          if (selectedCreditSource === "other") {
            if (transaction.shareholderId) return false;
          } else if (transaction.shareholderId !== selectedCreditSource) {
            return false;
          }
        } else if (
          transaction.type !== "Expense" ||
          transaction.categoryId !== transactionFilters.category
        ) {
          return false;
        }
      }
      if (search) {
        const amount = Number(transaction.amount || 0);
        const signedAmount = transaction.type === "Credit" ? amount : -amount;

        const amountTerms = [
          String(amount),
          formatPlainMoney(amount),
          formatMoney(amount),
          String(signedAmount),
          `${signedAmount >= 0 ? "+" : ""}${signedAmount}`,
          `${transaction.type === "Credit" ? "+" : "-"}${formatPlainMoney(amount)}`,
          `${transaction.type === "Credit" ? "+" : "-"}${formatMoney(amount)}`
        ].join(" ");

        const searchableText = [
          transaction.description,
          transaction.notes,
          transaction.type,
          transaction.date,
          transaction.date?.slice(0, 7),
          categoryById[transaction.categoryId]?.name,
          shareholderById[transaction.shareholderId]?.name,
          shareholderById[transaction.paidBy]?.name,
          transaction.paidByName,
          amountTerms
        ]
          .filter(Boolean)
          .join(" ")
          .toLowerCase();

        const compactSearch = search.replace(/[₹,\s]/g, "");
        const compactSearchableText = searchableText.replace(/[₹,\s]/g, "");
        const matchesCompactValue =
          compactSearch.length > 0 &&
          compactSearchableText.includes(compactSearch);

        if (!searchableText.includes(search) && !matchesCompactValue) return false;
      }
      return true;
    });

    const [sortKey, sortDirection] = transactionSort.split("-");
    const direction = sortDirection === "desc" ? -1 : 1;
    const textValue = (transaction, key) => {
      if (key === "type") return transaction.type || "";
      if (key === "description") {
        return transaction.type === "Credit"
          ? `Credit - ${shareholderById[transaction.shareholderId]?.name || "Other"}`
          : transaction.description || "";
      }
      if (key === "category") {
        return transaction.type === "Credit"
          ? "Credit"
          : categoryById[transaction.categoryId]?.name || "Uncategorised";
      }
      if (key === "paidBy") return transactionPaidByLabel(transaction);
      return "";
    };

    return filtered.slice().sort((a, b) => {
      let comparison = 0;

      if (sortKey === "serial") {
        comparison = Number(a.sortOrder || 0) - Number(b.sortOrder || 0);
      } else if (sortKey === "date" || sortKey === "month") {
        comparison = String(a.date || "").localeCompare(String(b.date || ""));
      } else if (sortKey === "amount") {
        comparison = Number(a.amount || 0) - Number(b.amount || 0);
      } else if (sortKey === "net") {
        const aNet = a.type === "Credit" ? Number(a.amount || 0) : -Number(a.amount || 0);
        const bNet = b.type === "Credit" ? Number(b.amount || 0) : -Number(b.amount || 0);
        comparison = aNet - bNet;
      } else {
        comparison = textValue(a, sortKey).localeCompare(textValue(b, sortKey), undefined, {
          numeric: true,
          sensitivity: "base"
        });
      }

      if (comparison === 0) {
        comparison = String(a.date || "").localeCompare(String(b.date || ""));
      }

      return comparison * direction;
    });
  }, [categoryById, data, shareholderById, transactionFilters, transactionSort]);

  const filteredTransactionTotals = useMemo(() => {
    const expenses = filteredTransactions
      .filter((transaction) => transaction.type === "Expense")
      .reduce((sum, transaction) => sum + transaction.amount, 0);
    const credits = filteredTransactions
      .filter((transaction) => transaction.type === "Credit")
      .reduce((sum, transaction) => sum + transaction.amount, 0);

    return {
      totalAmount: expenses + credits,
      expenses,
      credits,
      netEffect: credits - expenses
    };
  }, [filteredTransactions]);

  const deletedTransactionTotals = useMemo(() => {
    const expenses = deletedTransactions
      .filter((transaction) => transaction.type === "Expense")
      .reduce((sum, transaction) => sum + transaction.amount, 0);
    const credits = deletedTransactions
      .filter((transaction) => transaction.type === "Credit")
      .reduce((sum, transaction) => sum + transaction.amount, 0);

    return {
      expenses,
      credits,
      total: expenses + credits
    };
  }, [deletedTransactions]);

  const totalTransactionPages = Math.max(1, Math.ceil(filteredTransactions.length / PAGE_SIZE));
  const pagedTransactions = filteredTransactions.slice(
    (transactionPage - 1) * PAGE_SIZE,
    transactionPage * PAGE_SIZE
  );

  useEffect(() => {
    setTransactionPage(1);
  }, [transactionFilters, transactionSort]);

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
    setDeletedTransactions([]);
    setDeletePassword("");
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
    setWorkDraft({
      ...emptyWork(activeCategories),
      paidById: delvinPartnerId
    });
    setModal("works");
  }

  function openNewCredit() {
    setWorkDraft(emptyCredit(activeCategories));
    setModal("credit");
  }

  function openEditWork(work) {
    const nextDraft = {
      ...work,
      entryType: work.entryType === "Credit" ? "Credit" : "Expense",
      creditShareholderId: work.creditShareholderId || "",
      paidById: work.entryType === "Credit"
        ? ""
        : work.paidById || delvinPartnerId
    };
    setWorkDraft(nextDraft);
    setModal(nextDraft.entryType === "Credit" ? "credit" : "works");
  }

  function openEditTransaction(transaction) {
    if (!isAdmin) return;

    setDeletePassword("");
    setTransactionDraft({
      id: transaction.id,
      type: transaction.type,
      date: transaction.date,
      description: transaction.description || "",
      categoryId: transaction.categoryId || activeCategories[0]?.id || "",
      shareholderId: transaction.shareholderId || "",
      paidById: transaction.type === "Expense"
        ? transaction.paidById || delvinPartnerId
        : "",
      amount: transaction.amount,
      notes: transaction.notes || "",
      workId: transaction.workId || null
    });
    setModal("transaction");
  }

  async function saveTransaction(event) {
    event.preventDefault();
    if (!transactionDraft) return;

    const result = await adminRpc("mecardee_admin_update_transaction_v3", {
      p_id: transactionDraft.id,
      p_txn_date: transactionDraft.date,
      p_description: transactionDraft.description,
      p_category_id: transactionDraft.type === "Expense"
        ? transactionDraft.categoryId
        : null,
      p_shareholder_id: transactionDraft.type === "Credit" && transactionDraft.shareholderId
        ? transactionDraft.shareholderId
        : null,
      p_paid_by: transactionDraft.type === "Expense"
        ? transactionDraft.paidById
        : null,
      p_amount: Number(transactionDraft.amount || 0),
      p_notes: transactionDraft.notes
    }, `${transactionDraft.type} updated.`);

    if (result.ok) {
      setTransactionDraft(null);
      setDeletePassword("");
      setModal("");
    }
  }

  async function deleteTransaction() {
    if (!transactionDraft || !isAdmin) return;

    if (!deletePassword) {
      notify("Enter Delvin’s admin password before deleting.");
      return;
    }

    const description = transactionDraft.description || transactionDraft.type;
    if (!window.confirm(`Move "${description}" to the Deleted Entries Report?`)) return;

    const result = await adminRpc("mecardee_admin_delete_transaction", {
      p_id: transactionDraft.id,
      p_admin_password: deletePassword
    }, "Entry moved to the Deleted Entries Report.");

    if (result.ok) {
      setTransactionDraft(null);
      setDeletePassword("");
      setModal("");
      await loadDeletedTransactions(currentUser.token);
    }
  }

  async function saveWork(event) {
    event.preventDefault();
    if (!workDraft) return;

    const isCreditEntry = workDraft.entryType === "Credit";
    const creditSourceName = isCreditEntry
      ? shareholderById[workDraft.creditShareholderId]?.name || "Other"
      : workDraft.owner;

    const result = await adminRpc("mecardee_admin_save_work", {
      p_id: workDraft.id || null,
      p_title: workDraft.title,
      p_category_id: workDraft.categoryId,
      p_owner: creditSourceName,
      p_work_date: workDraft.workDate,
      p_deadline: isCreditEntry ? workDraft.workDate : workDraft.deadline,
      p_is_completed: true,
      p_entry_type: isCreditEntry ? "Credit" : "Expense",
      p_amount: Number(workDraft.amount || 0),
      p_credit_shareholder_id: isCreditEntry && workDraft.creditShareholderId
        ? workDraft.creditShareholderId
        : null,
      p_paid_by: isCreditEntry ? null : workDraft.paidById,
      p_notes: workDraft.notes,
      p_sort_order: Number(workDraft.sortOrder || 0)
    }, workDraft.id
      ? isCreditEntry ? "Credit updated." : "Work updated."
      : isCreditEntry ? "Credit added." : "Today’s work added.");

    if (result.ok) {
      setWorkDraft(isCreditEntry ? emptyCredit(activeCategories) : { ...emptyWork(activeCategories), paidById: delvinPartnerId });
    }
  }

  async function deleteWork(work) {
    if (!isAdmin) return;

    const adminPassword = window.prompt(
      `Enter Delvin’s admin password to delete "${work.title}".`
    );

    if (!adminPassword) return;

    if (!window.confirm(`Move "${work.title}" to the Deleted Entries Report?`)) return;

    const result = await adminRpc("mecardee_admin_delete_work_secure", {
      p_id: work.id,
      p_admin_password: adminPassword
    }, "Work moved to the Deleted Entries Report.");

    if (result.ok) {
      if (workDraft?.id === work.id) {
        setWorkDraft(work.entryType === "Credit"
          ? emptyCredit(activeCategories)
          : { ...emptyWork(activeCategories), paidById: delvinPartnerId });
      }
      await loadDeletedTransactions(currentUser.token);
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
      p_credit_shareholder_id: work.entryType === "Credit" && work.creditShareholderId
        ? work.creditShareholderId
        : null,
      p_paid_by: work.entryType === "Credit"
        ? null
        : work.paidById || delvinPartnerId,
      p_notes: work.notes,
      p_sort_order: work.sortOrder
    }, work.isCompleted ? "Work reopened." : "Work marked complete.");
  }

  function resetTransactionFilters() {
    setTransactionFilters({ from: "", to: "", type: "all", category: "all", search: "" });
    setTransactionSort("date-asc");
  }

  function toggleTransactionSort(key, defaultDirection = "asc") {
    setTransactionSort((current) => {
      const [currentKey, currentDirection] = current.split("-");
      if (currentKey !== key) return `${key}-${defaultDirection}`;
      return `${key}-${currentDirection === "asc" ? "desc" : "asc"}`;
    });
  }

  function transactionSortIcon(key) {
    const [currentKey, currentDirection] = transactionSort.split("-");
    if (currentKey !== key) return "\u2195";
    return currentDirection === "asc" ? "\u2191" : "\u2193";
  }

  function transactionDescriptionLabel(transaction) {
    if (transaction.type === "Credit") {
      return transaction.description || "Credit entry";
    }
    return transaction.description;
  }

  function transactionCategoryLabel(transaction) {
    if (transaction.type === "Credit") {
      return `Credit - ${shareholderById[transaction.shareholderId]?.name || "Unassigned"}`;
    }
    return categoryById[transaction.categoryId]?.name || "Uncategorised";
  }

  function transactionPaidByLabel(transaction) {
    if (transaction.type !== "Expense") return "—";
    return shareholderById[transaction.paidById]?.name || "Delvin";
  }

  function transactionFilterSummary() {
    const parts = [];

    if (transactionFilters.from) parts.push(`From ${formatDate(transactionFilters.from)}`);
    if (transactionFilters.to) parts.push(`To ${formatDate(transactionFilters.to)}`);
    if (transactionFilters.type !== "all") parts.push(`Type: ${transactionFilters.type}`);

    if (transactionFilters.category !== "all") {
      if (transactionFilters.category.startsWith("credit:")) {
        const selectedCreditSource = transactionFilters.category.slice("credit:".length);
        const sourceName = selectedCreditSource === "other"
          ? "Other"
          : shareholderById[selectedCreditSource]?.name || "Selected source";

        parts.push(`Credit source: ${sourceName}`);
      } else {
        parts.push(`Category: ${categoryById[transactionFilters.category]?.name || "Selected category"}`);
      }
    }

    if (transactionFilters.search.trim()) {
      parts.push(`Search: ${transactionFilters.search.trim()}`);
    }

    return parts.length ? parts.join(" | ") : "All transactions";
  }

  function exportFilteredTransactionsPdf() {
    if (!filteredTransactions.length) {
      notify("No filtered transactions to export.");
      return;
    }

    setIsExporting(true);

    try {
      const rows = filteredTransactions.map((transaction, index) => [
        index + 1,
        formatDate(transaction.date),
        transaction.date.slice(0, 7),
        transaction.type,
        transactionDescriptionLabel(transaction),
        transactionCategoryLabel(transaction),
        transactionPaidByLabel(transaction),
        { text: formatPlainMoney(transaction.amount), alignment: "right" },
        {
          text: `${transaction.type === "Credit" ? "+" : "-"}${formatPlainMoney(transaction.amount)}`,
          alignment: "right"
        }
      ]);

      const doc = {
        pageSize: "A4",
        pageOrientation: "landscape",
        pageMargins: [28, 32, 28, 32],
        content: [
          { text: "MECARDEE - FILTERED TRANSACTION REGISTER", style: "title" },
          {
            text: transactionFilterSummary(),
            style: "subtitle",
            margin: [0, 4, 0, 14]
          },
          {
            columns: [
              { stack: [{ text: "MATCHING RECORDS", style: "kpiLabel" }, { text: String(filteredTransactions.length), style: "kpiValue" }] },
              { stack: [{ text: "EXPENSES", style: "kpiLabel" }, { text: formatMoney(filteredTransactionTotals.expenses), style: "kpiValue" }] },
              { stack: [{ text: "CREDITS", style: "kpiLabel" }, { text: formatMoney(filteredTransactionTotals.credits), style: "kpiValue" }] },
              {
                stack: [
                  { text: "NET EFFECT", style: "kpiLabel" },
                  {
                    text: `${filteredTransactionTotals.netEffect >= 0 ? "+" : "-"}${formatMoney(Math.abs(filteredTransactionTotals.netEffect))}`,
                    style: "kpiValue"
                  }
                ]
              }
            ],
            columnGap: 12,
            margin: [0, 0, 0, 18]
          },
          {
            table: {
              headerRows: 1,
              widths: [25, 56, 44, 40, 120, 90, 55, 58, 62],
              body: [
                ["Sl.", "Date", "Month", "Type", "Description", "Category", "Paid by", "Amount (₹)", "Net Effect (₹)"],
                ...rows
              ]
            },
            layout: "lightHorizontalLines",
            fontSize: 7
          }
        ],
        styles: {
          title: { fontSize: 18, bold: true, color: "#071a17" },
          subtitle: { fontSize: 8, color: "#64736f" },
          kpiLabel: { fontSize: 8, bold: true, color: "#64736f" },
          kpiValue: { fontSize: 16, bold: true, color: "#10201d", margin: [0, 3, 0, 0] }
        },
        defaultStyle: { font: "Roboto", fontSize: 8, color: "#10201d" },
        footer(currentPage, pageCount) {
          return {
            text: `${data.project.name} · Filtered register · Page ${currentPage} of ${pageCount}`,
            alignment: "center",
            fontSize: 7,
            color: "#64736f",
            margin: [0, 8, 0, 0]
          };
        }
      };

      pdfMake.createPdf(doc).download(`mecardee-filtered-transactions-${toDateInput()}.pdf`);
      notify("Filtered transaction PDF downloaded.");
    } catch (error) {
      console.error("Filtered PDF export failed:", error);
      notify("Could not generate the filtered PDF.");
    } finally {
      setIsExporting(false);
    }
  }

  function exportFilteredTransactionsExcel() {
    if (!filteredTransactions.length) {
      notify("No filtered transactions to export.");
      return;
    }

    try {
      const escapeCell = (value) => String(value ?? "")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;");

      const transactionRows = filteredTransactions.map((transaction, index) => `
        <tr>
          <td>${index + 1}</td>
          <td>${escapeCell(formatDate(transaction.date))}</td>
          <td>${escapeCell(transaction.date.slice(0, 7))}</td>
          <td>${escapeCell(transaction.type)}</td>
          <td>${escapeCell(transactionDescriptionLabel(transaction))}</td>
          <td>${escapeCell(transactionCategoryLabel(transaction))}</td>
          <td>${escapeCell(transactionPaidByLabel(transaction))}</td>
          <td class="number">${transaction.amount}</td>
          <td class="number">${transaction.type === "Credit" ? transaction.amount : -transaction.amount}</td>
          <td>${escapeCell(transaction.notes)}</td>
        </tr>
      `).join("");

      const workbook = `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <style>
    body { font-family: Arial, sans-serif; color: #10201d; }
    table { border-collapse: collapse; width: 100%; }
    th, td { border: 1px solid #cfd8d3; padding: 7px; font-size: 11px; }
    th { background: #eaf0ec; font-weight: bold; }
    .title { font-size: 20px; font-weight: bold; background: #071a17; color: white; }
    .subtitle { color: #52645f; }
    .summary-label { background: #eaf0ec; font-weight: bold; }
    .summary-value { font-weight: bold; }
    .number { mso-number-format:"0"; text-align: right; }
  </style>
</head>
<body>
  <table>
    <tr><td class="title" colspan="10">Mecardee - Filtered Transaction Register</td></tr>
    <tr><td class="subtitle" colspan="10">${escapeCell(transactionFilterSummary())}</td></tr>
    <tr>
      <td class="summary-label">Matching records</td><td class="summary-value">${filteredTransactions.length}</td>
      <td class="summary-label">Expenses</td><td class="summary-value">${filteredTransactionTotals.expenses}</td>
      <td class="summary-label">Credits</td><td class="summary-value">${filteredTransactionTotals.credits}</td>
      <td class="summary-label">Net effect</td><td class="summary-value">${filteredTransactionTotals.netEffect}</td>
      <td></td><td></td>
    </tr>
    <tr><td colspan="10"></td></tr>
    <tr>
      <th>Sl. No.</th>
      <th>Date</th>
      <th>Month</th>
      <th>Type</th>
      <th>Description</th>
      <th>Category</th>
      <th>Paid by</th>
      <th>Amount (₹)</th>
      <th>Net Effect (₹)</th>
      <th>Notes</th>
    </tr>
    ${transactionRows}
  </table>
</body>
</html>`;

      const blob = new Blob(["\ufeff", workbook], {
        type: "application/vnd.ms-excel;charset=utf-8"
      });
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = `mecardee-filtered-transactions-${toDateInput()}.xls`;
      document.body.appendChild(link);
      link.click();
      link.remove();
      URL.revokeObjectURL(url);
      notify("Filtered Excel report downloaded.");
    } catch (error) {
      console.error("Excel export failed:", error);
      notify("Could not generate the Excel report.");
    }
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

      const partnerRows = partnerContributionReport.rows.map((row) => [
        row.name,
        { text: formatPlainMoney(row.recordedCashCredits), alignment: "right" },
        { text: formatPlainMoney(row.directExpensesPaid), alignment: "right" },
        { text: formatPlainMoney(row.calculatedUnrecordedContribution), alignment: "right" },
        { text: formatPlainMoney(row.totalContribution), alignment: "right" }
      ]);

      const transactionRows = data.transactions.map((transaction, index) => [
        index + 1,
        formatDate(transaction.date),
        transaction.date.slice(0, 7),
        transaction.type,
        transactionDescriptionLabel(transaction),
        transactionCategoryLabel(transaction),
        transactionPaidByLabel(transaction),
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
          {
            stack: [
              { text: "PARTNER CONTRIBUTION REPORT", style: "sectionTitle", margin: [0, 18, 0, 8] },
              ...(partnerContributionReport.hasExcessRecordedCredits ? [{
                text: "Warning: Recorded partner credits are higher than accounted business spending. Delvin's unrecorded contribution is shown as zero.",
                color: "#a13b32",
                fontSize: 8,
                margin: [0, 0, 0, 8]
              }] : []),
              {
                table: {
                  headerRows: 1,
                  widths: [75, 90, 90, 110, 90],
                  body: [
                    ["Partner", "Recorded Cash Credits", "Direct Expenses Paid", "Calculated Unrecorded", "Total Contribution"],
                    ...partnerRows
                  ]
                },
                layout: "lightHorizontalLines"
              }
            ]
          },
          { text: "TRANSACTION REGISTER", style: "sectionTitle", pageBreak: "before" },
          {
            table: {
              headerRows: 1,
              widths: [24, 52, 42, 38, 112, 82, 48, 56, 60],
              body: [
                ["Sl.", "Date", "Month", "Type", "Description", "Category", "Paid by", "Amount (₹)", "Net Effect (₹)"],
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

  function renderWorkList(items, emptyTitle, emptyMessage, allowAdd = false) {
    if (items.length === 0) {
      return (
        <div className="empty-state compact-work-empty">
          <span>＋</span>
          <h3>{emptyTitle}</h3>
          <p>{emptyMessage}</p>
          {allowAdd && isAdmin && (
            <button className="primary-button" type="button" onClick={openNewWork}>Add work</button>
          )}
        </div>
      );
    }

    return items.map((work) => {
      const category = categoryById[work.categoryId];
      const status = workStatus(work);

      return (
        <article className="work-card" key={work.id}>
          <div className={`status-dot ${status.toLowerCase()}`} />
          <div className="work-card-copy">
            <div className="task-meta">
              <span>{category?.icon || "•"} {category?.name || "Uncategorised"}</span>
              <span className={`status-badge ${status.toLowerCase()}`}>{status}</span>
              <span className="report-entry-badge expense">Expense entry</span>
            </div>
            <h3>{work.title}</h3>
            {work.notes && <p>{work.notes}</p>}
            <div className="work-details">
              <span>▣ Work date: {formatDate(work.workDate)}</span>
              <span>◷ Deadline: {formatDate(work.deadline)}</span>
              <span>👤 {work.owner || "Not assigned"}</span>
              <span>Paid by: {shareholderById[work.paidById]?.name || "Delvin"}</span>
              <span>₹ {formatMoney(work.amount)}</span>
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
    });
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
            {isAdmin && <button className="credit-action-button" type="button" onClick={openNewCredit}>Add credit</button>}
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
          <span className="summary-icon">{report.netExpense < 0 ? "＋" : report.netExpense > 0 ? "−" : "="}</span>
          <div>
            <small>
              {report.netExpense < 0
                ? "Remaining credit"
                : report.netExpense > 0
                  ? "Net expense"
                  : "Credit balance"}
            </small>
            <strong className="money-summary">{formatMoney(Math.abs(report.netExpense))}</strong>
          </div>
          <p>
            {report.netExpense < 0
              ? "Credits remaining after expenses"
              : report.netExpense > 0
                ? "Expenses exceed received credits"
                : "Expenses and credits are balanced"}
          </p>
        </article>
        
      </section>

      <section className="section-block shareholders-section" id="shareholders">
        <div className="shareholder-heading">
          <div>
            <span className="eyebrow">Capital contributors</span>
            <h2>Shareholders</h2>
          </div>
          <small>Calculated from recorded cash credits and direct expenses paid.</small>
        </div>

        <div className="shareholder-overview-layout">
        <div className="shareholder-grid">
          {partnerShareholders.map((shareholder, index) => (
            <article className="shareholder-card" key={shareholder.id}>
              <span className="share-index">{pad(index + 1)}</span>
              <div className="share-avatar">{shareholder.name.slice(0, 1).toUpperCase()}</div>
              <div>
                <small>Partner contribution</small>
                <strong>{shareholder.name}</strong>
                <p>{formatMoney(partnerContributionById[shareholder.id]?.totalContribution || 0)}</p>
              </div>
            </article>
          ))}
        </div>

          <article className="share-budget-circle-panel">
            <div
              className="share-budget-circle"
              style={{ background: shareBudgetCircle.gradient }}
              aria-label="Each partner contribution as a percentage of the total category budget"
            >
              <div className="share-budget-circle-center">
                <small>Share of total budget</small>

                <div className="share-budget-circle-values">
                  {shareBudgetCircle.rows.map((row) => (
                    <div className="share-budget-circle-row" key={row.id}>
                      <span>
                        <i style={{ background: row.color }} />
                        {row.name}
                      </span>
                      <strong>
                        {row.percentage.toFixed(row.percentage >= 100 ? 0 : 1)}%
                      </strong>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </article>
        </div>

        <div className="partner-contribution-report">
          <div className="partner-contribution-heading">
            <div>
              <span className="eyebrow">Contribution reconciliation</span>
              <h3>Partner contribution report</h3>
            </div>
            <small>Direct expenses are not entered again as credits.</small>
          </div>

          {partnerContributionReport.hasExcessRecordedCredits && (
            <div className="contribution-warning" role="alert">
              Recorded partner credits are higher than accounted business spending. Delvin’s calculated unrecorded contribution is shown as zero.
            </div>
          )}

          <div className="responsive-table partner-contribution-table-wrap">
            <table className="partner-contribution-table">
              <thead>
                <tr>
                  <th>Partner</th>
                  <th>Recorded Cash Credits</th>
                  <th>Direct Expenses Paid</th>
                  <th>Calculated Unrecorded Contribution</th>
                  <th>Total Contribution</th>
                </tr>
              </thead>
              <tbody>
                {partnerContributionReport.rows.map((row) => (
                  <tr key={row.id}>
                    <td><strong>{row.name}</strong></td>
                    <td>{formatMoney(row.recordedCashCredits)}</td>
                    <td>{formatMoney(row.directExpensesPaid)}</td>
                    <td>{formatMoney(row.calculatedUnrecordedContribution)}</td>
                    <td><strong>{formatMoney(row.totalContribution)}</strong></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="partner-contribution-note">
            Delvin’s direct-expense column is informational. His total uses recorded credits plus the calculated unrecorded contribution, so the same spending is not counted twice.
          </p>
        </div>
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
            <small>Total partner contributions</small>
            <strong>{formatMoney(totalShareAmount)}</strong>
          </article>
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
            <h2>Today’s work</h2>
            <p className="work-section-description">Open and completed works dated {formatDate(toDateInput())}.</p>
          </div>
          {isAdmin && <button className="primary-button" type="button" onClick={openNewWork}>＋ Add work</button>}
        </div>

        <div className="work-filter-panel work-category-filter">
          <select value={activeCategory} onChange={(event) => setActiveCategory(event.target.value)} aria-label="Filter works by category">
            <option value="all">All categories</option>
            {activeCategories.map((category) => <option value={category.id} key={category.id}>{category.name}</option>)}
          </select>
          <span>{todayWorks.length} today · {openWorks.length} open</span>
        </div>

        <div className="work-list today-work-list">
          {renderWorkList(
            todayWorks,
            "No work added for today",
            isAdmin ? "Use Add work to record today’s site activity." : "No site activity is dated today.",
            true
          )}
        </div>

        <div className="work-subsection-heading">
          <div>
            <span className="eyebrow">Pending work register</span>
            <h2>Open works</h2>
            <p>All incomplete works, sorted from newest work date to oldest.</p>
          </div>
          <span className="open-work-count">{openWorks.length} pending</span>
        </div>

        <div className="work-list open-work-list">
          {renderWorkList(
            openWorks,
            "No open work",
            "Every recorded work item has been completed."
          )}
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

          <article className="report-table-card partner-report-card">
            <h3>PARTNER CONTRIBUTION REPORT</h3>
            {partnerContributionReport.hasExcessRecordedCredits && (
              <div className="contribution-warning" role="alert">
                Recorded partner credits are higher than accounted business spending. Delvin’s calculated unrecorded contribution is shown as zero.
              </div>
            )}
            <div className="responsive-table">
              <table>
                <thead>
                  <tr>
                    <th>Partner</th>
                    <th>Recorded Cash Credits</th>
                    <th>Direct Expenses Paid</th>
                    <th>Calculated Unrecorded Contribution</th>
                    <th>Total Contribution</th>
                  </tr>
                </thead>
                <tbody>
                  {partnerContributionReport.rows.map((row) => (
                    <tr key={row.id}>
                      <td><strong>{row.name}</strong></td>
                      <td>{formatPlainMoney(row.recordedCashCredits)}</td>
                      <td>{formatPlainMoney(row.directExpensesPaid)}</td>
                      <td>{formatPlainMoney(row.calculatedUnrecordedContribution)}</td>
                      <td><strong>{formatPlainMoney(row.totalContribution)}</strong></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </article>

          <div className="report-basis">
            <strong>REPORT BASIS</strong>
            <p>
              All corrected entries from the reviewed workbook are included. Existing expenses without a payer are assigned to Delvin. Direct expenses paid by Dantees or Dennis count as partner contributions and must not be entered again as credits. Net Expense = Total Expenses - Total Credits.
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
              <p>Click any column heading to sort · Reporting period: {formatDate(report.periodStart)} to {formatDate(report.periodEnd)}</p>
            </div>
            <div className="transaction-title-actions">
              <span className="transaction-count-pill">{filteredTransactions.length} records</span>
              <div className="transaction-export-actions">
                <button
                  className="secondary-button transaction-export-button"
                  type="button"
                  onClick={exportFilteredTransactionsExcel}
                  disabled={!filteredTransactions.length}
                >
                  Export Excel
                </button>
                <button
                  className="secondary-button transaction-export-button"
                  type="button"
                  onClick={exportFilteredTransactionsPdf}
                  disabled={!filteredTransactions.length || isExporting}
                >
                  {isExporting ? "Preparing…" : "Export PDF"}
                </button>
                {isAdmin && (
                  <button
                    className="secondary-button transaction-export-button deleted-report-button"
                    type="button"
                    onClick={() => {
                      loadDeletedTransactions(currentUser.token);
                      setModal("deleted");
                    }}
                  >
                    Deleted entries
                  </button>
                )}
              </div>
            </div>
          </div>

          <div className="transaction-filter-grid">
            <label>From date
              <input type="date" value={transactionFilters.from} onChange={(event) => setTransactionFilters({ ...transactionFilters, from: event.target.value })} />
            </label>
            <label>To date
              <input type="date" value={transactionFilters.to} onChange={(event) => setTransactionFilters({ ...transactionFilters, to: event.target.value })} />
            </label>
            <label>Type
              <select
                value={transactionFilters.type}
                onChange={(event) => setTransactionFilters({
                  ...transactionFilters,
                  type: event.target.value,
                  category: "all"
                })}
              >
                <option value="all">All types</option>
                <option value="Expense">Expense</option>
                <option value="Credit">Credit</option>
              </select>
            </label>
            <label>{transactionFilters.type === "Credit" ? "Credit received from" : "Category"}
              <select
                value={transactionFilters.category}
                onChange={(event) => setTransactionFilters({
                  ...transactionFilters,
                  category: event.target.value
                })}
              >
                <option value="all">
                  {transactionFilters.type === "Credit" ? "All credit sources" : "All categories"}
                </option>

                {transactionFilters.type === "Credit" ? (
                  <>
                    {partnerShareholders.map((shareholder) => (
                      <option value={`credit:${shareholder.id}`} key={shareholder.id}>
                        Credit - {shareholder.name}
                      </option>
                    ))}
                    <option value="credit:other">Credit - Unassigned (legacy)</option>
                  </>
                ) : (
                  activeCategories.map((category) => (
                    <option value={category.id} key={category.id}>{category.name}</option>
                  ))
                )}
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

          <div className="filtered-transaction-totals" aria-live="polite">
            <article className="filtered-total-card primary">
              <small>Filtered total amount</small>
              <strong>{formatMoney(filteredTransactionTotals.totalAmount)}</strong>
              <span>{filteredTransactions.length} matching transaction{filteredTransactions.length === 1 ? "" : "s"}</span>
            </article>
            <article className="filtered-total-card expense">
              <small>Filtered expenses</small>
              <strong>{formatMoney(filteredTransactionTotals.expenses)}</strong>
            </article>
            <article className="filtered-total-card credit">
              <small>Filtered credits</small>
              <strong>{formatMoney(filteredTransactionTotals.credits)}</strong>
            </article>
            <article className={`filtered-total-card ${filteredTransactionTotals.netEffect >= 0 ? "credit" : "expense"}`}>
              <small>Filtered net effect</small>
              <strong>{filteredTransactionTotals.netEffect >= 0 ? "+" : "−"}{formatMoney(Math.abs(filteredTransactionTotals.netEffect))}</strong>
            </article>
          </div>

          <div className="responsive-table transaction-table-wrap">
            <table className="transaction-table">
              <thead>
                <tr>
                  <th>
                    <button className="transaction-sort-button" type="button" onClick={() => toggleTransactionSort("serial", "asc")}>
                      <span>Sl. No.</span><b>{transactionSortIcon("serial")}</b>
                    </button>
                  </th>
                  <th>
                    <button className="transaction-sort-button" type="button" onClick={() => toggleTransactionSort("date", "asc")}>
                      <span>Date</span><b>{transactionSortIcon("date")}</b>
                    </button>
                  </th>
                  <th>
                    <button className="transaction-sort-button" type="button" onClick={() => toggleTransactionSort("month", "asc")}>
                      <span>Month</span><b>{transactionSortIcon("month")}</b>
                    </button>
                  </th>
                  <th>
                    <button className="transaction-sort-button" type="button" onClick={() => toggleTransactionSort("type", "asc")}>
                      <span>Type</span><b>{transactionSortIcon("type")}</b>
                    </button>
                  </th>
                  <th>
                    <button className="transaction-sort-button" type="button" onClick={() => toggleTransactionSort("description", "asc")}>
                      <span>Description</span><b>{transactionSortIcon("description")}</b>
                    </button>
                  </th>
                  <th>
                    <button className="transaction-sort-button" type="button" onClick={() => toggleTransactionSort("category", "asc")}>
                      <span>Category</span><b>{transactionSortIcon("category")}</b>
                    </button>
                  </th>
                  <th>
                    <button className="transaction-sort-button" type="button" onClick={() => toggleTransactionSort("paidBy", "asc")}>
                      <span>Paid by</span><b>{transactionSortIcon("paidBy")}</b>
                    </button>
                  </th>
                  <th>
                    <button className="transaction-sort-button" type="button" onClick={() => toggleTransactionSort("amount", "desc")}>
                      <span>Amount (₹)</span><b>{transactionSortIcon("amount")}</b>
                    </button>
                  </th>
                  <th>
                    <button className="transaction-sort-button" type="button" onClick={() => toggleTransactionSort("net", "desc")}>
                      <span>Net Effect (₹)</span><b>{transactionSortIcon("net")}</b>
                    </button>
                  </th>
                  {isAdmin && <th className="transaction-action-heading">Edit</th>}
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
                      <td>{transactionDescriptionLabel(transaction)}</td>
                      <td>{transactionCategoryLabel(transaction)}</td>
                      <td>{transactionPaidByLabel(transaction)}</td>
                      <td>{formatPlainMoney(transaction.amount)}</td>
                      <td className={transaction.type === "Credit" ? "credit-effect" : "expense-effect"}>
                        {transaction.type === "Credit" ? "+" : "-"}{formatPlainMoney(transaction.amount)}
                      </td>
                      {isAdmin && (
                        <td className="transaction-edit-cell">
                          <button
                              className="transaction-edit-button"
                              type="button"
                              onClick={() => openEditTransaction(transaction)}
                              aria-label={`Edit ${transaction.description}`}
                              title="Edit transaction"
                            >
                              {"\u270E"}
                            </button>
                        </td>
                      )}
                    </tr>
                  );
                })}
                {pagedTransactions.length === 0 && (
                  <tr><td colSpan={isAdmin ? 10 : 9} className="empty-table-row">No transactions match the selected filters.</td></tr>
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

            {isAdmin && (
              <section className="account-setting-section admin-share-settings">
                <div className="account-section-heading">
                  <span>03</span>
                  <div>
                    <h3>Shareholder settings</h3>
                    <p>Edit shareholder names, amounts and display order from the administrator settings.</p>
                  </div>
                </div>
                <div className="account-quick-actions">
                  <button className="secondary-button" type="button" onClick={() => setModal("shares")}>
                    Edit shareholders and shares
                  </button>
                </div>
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
                <label>Budget (₹)<input className="plain-amount-input" name="budget" type="number" min="0" step="1" defaultValue={category.budget} /></label>
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
            <input className="plain-amount-input" name="budget" type="number" min="0" step="1" placeholder="Budget" />
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
                <label>Share amount (₹)<input className="plain-amount-input" name="amount" type="number" min="0" step="1" defaultValue={shareholder.amount} /></label>
                <label>Order<input name="sortOrder" type="number" step="1" defaultValue={shareholder.sortOrder} /></label>
                <button className="small-button" type="submit" disabled={isSyncing}>Save share</button>
              </form>
            ))}
          </div>
          <form className="new-editor-row share-add-row" onSubmit={(event) => saveShareholder(event, null)}>
            <div><span className="eyebrow">Optional</span><h3>Add shareholder</h3></div>
            <input name="name" placeholder="Name" required />
            <input className="plain-amount-input" name="amount" type="number" min="0" step="1" placeholder="Share amount" />
            <input name="sortOrder" type="number" step="1" placeholder="Order" />
            <button className="primary-button" type="submit" disabled={isSyncing}>Add shareholder</button>
          </form>
        </Modal>
      )}
      {modal === "deleted" && isAdmin && (
        <Modal title="Deleted Entries Report" eyebrow="Administrator audit report" onClose={() => setModal("")} wide>
          <div className="deleted-report-page">
            <div className="deleted-report-heading">
              <div>
                <span className="eyebrow">Password-protected deletion history</span>
                <h3>{deletedTransactions.length} deleted entr{deletedTransactions.length === 1 ? "y" : "ies"}</h3>
                <p>Entries are archived here after deletion and are removed from active financial totals.</p>
              </div>
              <button
                className="secondary-button"
                type="button"
                onClick={() => loadDeletedTransactions(currentUser.token)}
                disabled={deletedEntriesLoading}
              >
                {deletedEntriesLoading ? "Refreshing…" : "Refresh report"}
              </button>
            </div>

            <div className="deleted-report-totals">
              <article>
                <small>Deleted entries</small>
                <strong>{deletedTransactions.length}</strong>
              </article>
              <article>
                <small>Deleted expenses</small>
                <strong>{formatMoney(deletedTransactionTotals.expenses)}</strong>
              </article>
              <article>
                <small>Deleted credits</small>
                <strong>{formatMoney(deletedTransactionTotals.credits)}</strong>
              </article>
              <article>
                <small>Total deleted amount</small>
                <strong>{formatMoney(deletedTransactionTotals.total)}</strong>
              </article>
            </div>

            <div className="responsive-table deleted-report-table-wrap">
              <table className="deleted-report-table">
                <thead>
                  <tr>
                    <th>Deleted on</th>
                    <th>Entry date</th>
                    <th>Type</th>
                    <th>Description</th>
                    <th>Category / source</th>
                    <th>Paid by</th>
                    <th>Amount (₹)</th>
                    <th>Deleted by</th>
                  </tr>
                </thead>
                <tbody>
                  {deletedTransactions.map((transaction) => (
                    <tr key={transaction.id}>
                      <td>{transaction.deletedAt ? new Intl.DateTimeFormat("en-IN", {
                        day: "numeric",
                        month: "short",
                        year: "numeric",
                        hour: "numeric",
                        minute: "2-digit"
                      }).format(new Date(transaction.deletedAt)) : "—"}</td>
                      <td>{formatDate(transaction.date)}</td>
                      <td><span className={`transaction-type ${transaction.type.toLowerCase()}`}>{transaction.type}</span></td>
                      <td>
                        <strong>{transaction.description}</strong>
                        {transaction.notes && <small>{transaction.notes}</small>}
                      </td>
                      <td>
                        {transaction.type === "Credit"
                          ? `Credit - ${transaction.shareholderName || "Unassigned"}`
                          : transaction.categoryName || categoryById[transaction.categoryId]?.name || "Uncategorised"}
                      </td>
                      <td>{transaction.type === "Expense" ? transaction.paidByName || "Delvin" : "—"}</td>
                      <td>{formatPlainMoney(transaction.amount)}</td>
                      <td>{transaction.deletedBy}</td>
                    </tr>
                  ))}
                  {!deletedEntriesLoading && deletedTransactions.length === 0 && (
                    <tr>
                      <td colSpan="8" className="empty-table-row">No entries have been deleted.</td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </Modal>
      )}

      {modal === "transaction" && isAdmin && transactionDraft && (
        <Modal
          title={`Edit ${transactionDraft.type.toLowerCase()}`}
          eyebrow="Administrator controls"
          onClose={() => {
            setTransactionDraft(null);
            setDeletePassword("");
            setModal("");
          }}
        >
          <form className="transaction-edit-form" onSubmit={saveTransaction}>
            <div className="transaction-edit-intro">
              <span className="eyebrow">{transactionDraft.type} register</span>
              <h3>{transactionDraft.description}</h3>
              <p>Correct this entry or move it to the password-protected Deleted Entries Report.</p>
            </div>

            <label className="full-field">Description
              <input
                autoFocus
                required
                value={transactionDraft.description}
                onChange={(event) => setTransactionDraft({
                  ...transactionDraft,
                  description: event.target.value
                })}
              />
            </label>

            <label>Transaction date
              <input
                type="date"
                required
                value={transactionDraft.date}
                onChange={(event) => setTransactionDraft({
                  ...transactionDraft,
                  date: event.target.value
                })}
              />
            </label>

            {transactionDraft.type === "Expense" ? (
              <>
                <label>Category
                  <select
                    required
                    value={transactionDraft.categoryId}
                    onChange={(event) => setTransactionDraft({
                      ...transactionDraft,
                      categoryId: event.target.value
                    })}
                  >
                    {activeCategories.map((category) => (
                      <option value={category.id} key={category.id}>{category.name}</option>
                    ))}
                  </select>
                </label>
                <label>Paid by
                  <select
                    required
                    value={transactionDraft.paidById}
                    onChange={(event) => setTransactionDraft({
                      ...transactionDraft,
                      paidById: event.target.value
                    })}
                  >
                    {partnerShareholders.map((partner) => (
                      <option value={partner.id} key={partner.id}>{partner.name}</option>
                    ))}
                  </select>
                </label>
              </>
            ) : (
              <label>Credit received from
                <select
                  required
                  value={transactionDraft.shareholderId}
                  onChange={(event) => setTransactionDraft({
                    ...transactionDraft,
                    shareholderId: event.target.value
                  })}
                >
                  <option value="" disabled>Select partner</option>
                  {partnerShareholders.map((shareholder) => (
                    <option value={shareholder.id} key={shareholder.id}>{shareholder.name}</option>
                  ))}
                </select>
              </label>
            )}

            <label className="full-field">Amount (₹)
              <input
                className="plain-amount-input"
                type="number"
                inputMode="numeric"
                min="1"
                step="1"
                required
                placeholder="Enter amount"
                value={transactionDraft.amount === 0 ? "" : transactionDraft.amount}
                onChange={(event) => setTransactionDraft({
                  ...transactionDraft,
                  amount: Number(event.target.value || 0)
                })}
              />
            </label>

            <label className="full-field">Notes
              <textarea
                value={transactionDraft.notes}
                onChange={(event) => setTransactionDraft({
                  ...transactionDraft,
                  notes: event.target.value
                })}
                placeholder="Optional notes"
              />
            </label>

            <div className="transaction-delete-zone full-field">
              <div>
                <strong>Delete this entry</strong>
                <p>Enter Delvin’s current admin password. The entry will remain visible in the Deleted Entries Report.</p>
              </div>
              <label>Admin password
                <input
                  type="password"
                  autoComplete="current-password"
                  value={deletePassword}
                  onChange={(event) => setDeletePassword(event.target.value)}
                  placeholder="Required only for deletion"
                />
              </label>
              <button
                className="delete-button secure-delete-button"
                type="button"
                onClick={deleteTransaction}
                disabled={isSyncing || !deletePassword}
              >
                Delete entry
              </button>
            </div>

            <div className="modal-actions full-field">
              <button className="secondary-button" type="button" onClick={() => {
                setTransactionDraft(null);
                setDeletePassword("");
                setModal("");
              }}>Cancel</button>
              <button className="primary-button" type="submit" disabled={isSyncing}>Save changes</button>
            </div>
          </form>
        </Modal>
      )}

      {modal === "credit" && isAdmin && workDraft && (
        <Modal title="Credit entries" eyebrow="Administrator controls" onClose={() => setModal("")} wide>
          <div className="work-editor-layout">
            <form className="work-editor-form" onSubmit={saveWork}>
              <div className="work-editor-title">
                <span className="eyebrow">{workDraft.id ? "Edit selected credit" : "Add credit"}</span>
                <h3>{workDraft.id ? workDraft.title : "New credit entry"}</h3>
              </div>
              <label className="full-field">Description
                <input
                  autoFocus
                  required
                  value={workDraft.title}
                  onChange={(event) => setWorkDraft({ ...workDraft, title: event.target.value })}
                  placeholder="Enter the reason or details for this credit"
                />
              </label>
              <div className="credit-description-preview full-field">
                <span>Report category</span>
                <strong>Credit - {shareholderById[workDraft.creditShareholderId]?.name || "Other"}</strong>
              </div>
              <label>Credit date
                <input type="date" required value={workDraft.workDate} onChange={(event) => setWorkDraft({ ...workDraft, workDate: event.target.value })} />
              </label>
              <label>Credit received from
                <select
                  required
                  value={workDraft.creditShareholderId}
                  onChange={(event) => setWorkDraft({ ...workDraft, creditShareholderId: event.target.value })}
                >
                  <option value="" disabled>Select partner</option>
                  {partnerShareholders.map((shareholder) => (
                    <option value={shareholder.id} key={shareholder.id}>{shareholder.name}</option>
                  ))}
                </select>
              </label>
              <label>Credit amount (₹)
                <input
                  className="plain-amount-input"
                  type="number"
                  min="0"
                  step="1"
                  required
                  placeholder="Enter amount"
                  value={workDraft.amount === 0 ? "" : workDraft.amount}
                  onChange={(event) => setWorkDraft({ ...workDraft, amount: Number(event.target.value || 0) })}
                />
              </label>
              <label className="full-field">Notes
                <textarea value={workDraft.notes} onChange={(event) => setWorkDraft({ ...workDraft, notes: event.target.value })} placeholder="Credit details for the transaction register" />
              </label>
              <div className="modal-actions full-field">
                {workDraft.id && <button className="delete-button" type="button" onClick={() => deleteWork(workDraft)}>Delete</button>}
                <button className="secondary-button" type="button" onClick={() => setWorkDraft(emptyCredit(activeCategories))}>Clear</button>
                <button className="primary-button" type="submit" disabled={isSyncing}>{workDraft.id ? "Save credit" : "Add credit"}</button>
              </div>
            </form>

            <aside className="work-manager-list">
              <div><span className="eyebrow">Credit history</span><h3>Select to edit</h3></div>
              <div className="work-manager-scroll">
                {data.works.filter((work) => work.entryType === "Credit").map((work) => (
                  <button type="button" className={workDraft.id === work.id ? "selected" : ""} onClick={() => openEditWork(work)} key={work.id}>
                    <span>₹</span>
                    <div>
                      <strong>{work.title || "Credit entry"}</strong>
                      <small>Credit - {shareholderById[work.creditShareholderId]?.name || "Other"} · {formatDate(work.workDate)} · ₹ {formatMoney(work.amount)}</small>
                    </div>
                  </button>
                ))}
                {data.works.filter((work) => work.entryType === "Credit").length === 0 && (
                  <div className="empty-state compact"><p>No credit entries yet.</p></div>
                )}
              </div>
            </aside>
          </div>
        </Modal>
      )}
      {modal === "works" && isAdmin && workDraft && (
        <Modal title="Edit works" eyebrow="Administrator controls" onClose={() => setModal("")} wide>
          <div className="work-editor-layout works-editor-layout">
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

              <label>Paid by
                <select
                  required
                  value={workDraft.paidById}
                  onChange={(event) => setWorkDraft({ ...workDraft, paidById: event.target.value })}
                >
                  {partnerShareholders.map((partner) => (
                    <option value={partner.id} key={partner.id}>{partner.name}</option>
                  ))}
                </select>
              </label>
              <label>Work date
                <input type="date" required value={workDraft.workDate} onChange={(event) => setWorkDraft({ ...workDraft, workDate: event.target.value })} />
              </label>
              <label>Deadline
                <input type="date" required value={workDraft.deadline} onChange={(event) => setWorkDraft({ ...workDraft, deadline: event.target.value })} />
              </label>
              <label>Expense amount (₹)
                <input
                  className="plain-amount-input"
                  type="number"
                  min="0"
                  step="1"
                  required
                  placeholder="Enter amount"
                  value={workDraft.amount === 0 ? "" : workDraft.amount}
                  onChange={(event) => setWorkDraft({ ...workDraft, amount: Number(event.target.value || 0) })}
                />
              </label>

              <label className="full-field">Notes
                <textarea value={workDraft.notes} onChange={(event) => setWorkDraft({ ...workDraft, notes: event.target.value })} placeholder="Details for the work card and report" />
              </label>
              <div className="modal-actions full-field">
                {workDraft.id && <button className="delete-button" type="button" onClick={() => deleteWork(workDraft)}>Delete</button>}
                <button className="secondary-button" type="button" onClick={() => setWorkDraft({ ...emptyWork(activeCategories), paidById: delvinPartnerId })}>Clear</button>
                <button className="primary-button" type="submit" disabled={isSyncing}>{workDraft.id ? "Save work" : "Add work"}</button>
              </div>
            </form>

            <aside className="work-manager-list">
              <div>
                <span className="eyebrow">Existing works</span>
                <h3>All works · {editableWorks.length}</h3>
                <p className="work-list-order-note">Open works appear first, followed by completed works. Newest dates appear first.</p>
              </div>
              <div className="work-manager-scroll">
                {editableWorks.map((work) => (
                  <button type="button" className={workDraft.id === work.id ? "selected" : ""} onClick={() => openEditWork(work)} key={work.id}>
                    <span>{categoryById[work.categoryId]?.icon || "•"}</span>
                    <div>
                      <strong>{work.title}</strong>
                      <small>{categoryById[work.categoryId]?.name || "Uncategorised"} · {formatDate(work.workDate)} · {workStatus(work)}</small>
                    </div>
                  </button>
                ))}
                {editableWorks.length === 0 && (
                  <div className="empty-state compact"><p>No work items have been added yet.</p></div>
                )}
              </div>
            </aside>
          </div>
        </Modal>
      )}

      {toast && <div className="toast">{toast}</div>}
    </main>
  );
}
