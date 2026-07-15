import React from "react";
import {
  Document, Page, Text, View, StyleSheet, Font, renderToBuffer
} from "@react-pdf/renderer";
import { NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const PHASES = [
  { id: "site", name: "Site & Civil", icon: "▦" },
  { id: "water", name: "Water & Drainage", icon: "≈" },
  { id: "electrical", name: "Electrical & Safety", icon: "ϟ" },
  { id: "equipment", name: "Equipment Installation", icon: "⚙" },
  { id: "brand", name: "Branding & Customer Area", icon: "✦" },
  { id: "launch", name: "Staff & Launch", icon: "✓" }
];

Font.register({
  family: "DM Sans",
  fonts: [
    { src: "https://fonts.gstatic.com/s/dmsans/v15/rP2Hp2ywxg089UriCZOIHQ.ttf", fontWeight: 400 },
    { src: "https://fonts.gstatic.com/s/dmsans/v15/rP2Cp2ywxg089UriAWCrCBimCw.ttf", fontWeight: 700 }
  ]
});
Font.register({
  family: "Manrope",
  fonts: [
    { src: "https://fonts.gstatic.com/s/manrope/v15/xn7gYHE41ni1AdIRggexSg.ttf", fontWeight: 700 },
    { src: "https://fonts.gstatic.com/s/manrope/v15/xn7gYHE41ni1AdIRggexSg.ttf", fontWeight: 800 }
  ]
});

const css = StyleSheet.create({
  cover: {
    backgroundColor: "#071a17",
    color: "#ffffff",
    padding: "50 60",
    flexDirection: "column",
    justifyContent: "space-between",
    minHeight: "100%"
  },
  coverTop: { flexDirection: "row", alignItems: "center", marginBottom: 30 },
  brandBox: {
    width: 52, height: 52,
    backgroundColor: "#d7ff4f",
    borderRadius: 12,
    justifyContent: "center", alignItems: "center",
    marginRight: 14
  },
  brandM: { fontFamily: "Manrope", fontWeight: 800, fontSize: 26, color: "#071a17" },
  companyName: { fontFamily: "Manrope", fontWeight: 700, fontSize: 18, color: "#ffffff" },
  coverSubtitle: { fontSize: 9, color: "rgba(255,255,255,0.45)", letterSpacing: 1.5, textTransform: "uppercase" },
  coverCenter: { flex: 1, paddingVertical: 40 },
  eyebrow: { fontSize: 9, color: "#49d6bd", letterSpacing: 2, textTransform: "uppercase", marginBottom: 10 },
  coverTitle: { fontFamily: "Manrope", fontWeight: 800, fontSize: 46, lineHeight: 1.05, letterSpacing: -2, color: "#ffffff", marginBottom: 20 },
  locationPill: {
    backgroundColor: "rgba(255,255,255,0.06)",
    borderWidth: 1, borderColor: "rgba(255,255,255,0.18)",
    borderRadius: 999, paddingVertical: 6, paddingHorizontal: 14,
    fontSize: 10, color: "rgba(255,255,255,0.7)", alignSelf: "flex-start"
  },
  coverBottom: { flexDirection: "row", gap: 50 },
  statLabel: { fontSize: 8, color: "rgba(255,255,255,0.4)", letterSpacing: 1.2, textTransform: "uppercase", marginBottom: 4 },
  statValue: { fontFamily: "Manrope", fontWeight: 800, fontSize: 32, color: "#ffffff" },
  statNote: { fontSize: 10, color: "#d7ff4f", marginTop: 2 },
  coverMeta: { fontSize: 9, color: "rgba(255,255,255,0.28)", marginTop: 30 },

  page: { padding: "48 56", backgroundColor: "#f5f7f3" },
  sectionTitle: {
    fontFamily: "Manrope", fontWeight: 800, fontSize: 22, letterSpacing: -1,
    color: "#071a17", borderBottomWidth: 2, borderBottomColor: "#dfe6e2",
    paddingBottom: 10, marginBottom: 24, marginTop: 10
  },
  kpiRow: { flexDirection: "row", gap: 12, marginBottom: 20 },
  kpiCard: {
    flex: 1, backgroundColor: "#ffffff", borderWidth: 1, borderColor: "#dfe6e2",
    borderRadius: 12, padding: 18
  },
  kpiPrimary: { backgroundColor: "#071a17", borderColor: "#071a17" },
  kpiDanger: { backgroundColor: "#fff0ee", borderColor: "#f1c9c5" },
  kpiLabel: { fontSize: 8, color: "#64736f", letterSpacing: 0.8, textTransform: "uppercase", marginBottom: 6 },
  kpiPrimaryLabel: { color: "rgba(255,255,255,0.5)" },
  kpiValue: { fontFamily: "Manrope", fontWeight: 800, fontSize: 26, letterSpacing: -1, color: "#071a17" },
  kpiNote: { fontSize: 9, color: "#64736f", marginTop: 4 },

  overdueHeader: {
    backgroundColor: "#fff0ee", borderWidth: 1, borderColor: "#f1c9c5",
    borderBottomWidth: 0, borderRadius: "10 10 0 0",
    padding: "12 18", flexDirection: "row", alignItems: "center"
  },
  overdueHeaderText: { fontFamily: "Manrope", fontWeight: 800, fontSize: 13, color: "#d6493f" },
  overdueTable: { borderWidth: 1, borderColor: "#f1c9c5", borderTopWidth: 0, borderRadius: "0 0 10 10", marginBottom: 24 },
  tableRow: { flexDirection: "row", padding: "8 14", borderBottomWidth: 1, borderBottomColor: "#f1c9c5" },
  tableRowAlt: { backgroundColor: "#fffaf9" },
  tableHeader: { backgroundColor: "#fff0ee" },
  th: { fontSize: 7, color: "#d6493f", letterSpacing: 0.8, textTransform: "uppercase", fontWeight: 700 },
  td: { fontSize: 10, color: "#10201d" },
  tdMuted: { color: "#64736f" },
  tdDanger: { color: "#d6493f", fontWeight: 700 },

  phaseSection: { marginBottom: 30 },
  phaseHeader: { flexDirection: "row", justifyContent: "space-between", alignItems: "center", marginBottom: 8 },
  phaseLeft: { flexDirection: "row", alignItems: "center" },
  phaseIconBox: {
    width: 34, height: 34, backgroundColor: "#dff8f2",
    borderRadius: 10, justifyContent: "center", alignItems: "center",
    marginRight: 10
  },
  phaseIcon: { fontSize: 14 },
  phaseName: { fontFamily: "Manrope", fontWeight: 700, fontSize: 14, color: "#10201d" },
  phaseProgress: { fontFamily: "Manrope", fontWeight: 800, fontSize: 18, color: "#071a17" },
  phaseMeta: { flexDirection: "row", alignItems: "center", gap: 10 },
  phaseMetaText: { fontSize: 9, color: "#64736f" },
  progressBar: { height: 6, backgroundColor: "#f5f7f3", borderRadius: 6, marginBottom: 6 },
  progressFill: { height: 6, backgroundColor: "#49d6bd", borderRadius: 6 },
  phaseCount: { fontSize: 9, color: "#64736f", marginBottom: 12 },

  taskTable: { marginBottom: 20 },
  taskTh: { fontSize: 7, color: "#9aaba6", letterSpacing: 0.8, textTransform: "uppercase", fontWeight: 700 },
  taskTd: { fontSize: 10, color: "#10201d" },
  taskTdMuted: { color: "#64736f" },

  footer: {
    padding: "12 56",
    borderTopWidth: 1, borderTopColor: "#dfe6e2",
    flexDirection: "row", justifyContent: "space-between"
  },
  footerText: { fontSize: 8, color: "#9aaba6" },
  badgeOk: { backgroundColor: "#eff8e5", color: "#4b8618", borderRadius: 999, paddingVertical: 3, paddingHorizontal: 8, fontSize: 8, fontWeight: 700, overflow: "hidden" },
  badgeProgress: { backgroundColor: "#dff8f2", color: "#087666", borderRadius: 999, paddingVertical: 3, paddingHorizontal: 8, fontSize: 8, fontWeight: 700, overflow: "hidden" },
  badgePending: { backgroundColor: "#f5f7f3", color: "#64736f", borderRadius: 999, paddingVertical: 3, paddingHorizontal: 8, fontSize: 8, fontWeight: 700, overflow: "hidden" },
  badgeDanger: { backgroundColor: "#fff0ee", color: "#d6493f", borderRadius: 999, paddingVertical: 3, paddingHorizontal: 8, fontSize: 8, fontWeight: 700, overflow: "hidden" },
});

function parseLocalDate(value) {
  if (value === null || value === undefined || value === "") {
    return null;
  }

  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : value;
  }

  const text = String(value).trim();

  if (!text) {
    return null;
  }

  let date;

  // Supabase date column: 2026-07-15
  if (/^\d{4}-\d{2}-\d{2}$/.test(text)) {
    date = new Date(`${text}T12:00:00`);
  } else {
    // ISO timestamps and other valid date strings
    date = new Date(text);
  }

  return Number.isNaN(date.getTime()) ? null : date;
}
function startOfToday() {
  const d = new Date(); d.setHours(0, 0, 0, 0); return d;
}
function statusFor(progress, deadline) {
  if (progress >= 100) return "Completed";
  const d = parseLocalDate(deadline);
  if (d && d < startOfToday()) return "Overdue";
  if (progress > 0) return "In progress";
  return "Not started";
}
function formatDate(
  value,
  opts = { day: "numeric", month: "long", year: "numeric" }
) {
  const date = parseLocalDate(value);

  if (!date) {
    return "Not set";
  }

  try {
    return new Intl.DateTimeFormat("en-IN", opts).format(date);
  } catch {
    return "Not set";
  }
}
function getReportDate() {
  return new Intl.DateTimeFormat("en-IN", { day: "numeric", month: "long", year: "numeric" }).format(new Date());
}
function col(text, style, width) {
  return <Text style={[css.td, style]}>{text}</Text>;
}

function CoverPage({ project, overallProgress, completedCount, totalTasks, daysRemaining }) {
  return (
    <Page size="A4" style={css.cover}>
      <View>
        <View style={css.coverTop}>
          <View style={css.brandBox}><Text style={css.brandM}>M</Text></View>
          <View>
            <Text style={css.companyName}>{project.name}</Text>
            <Text style={css.coverSubtitle}>Launch Tracker · Project Report</Text>
          </View>
        </View>
        <View style={css.coverCenter}>
          <Text style={css.eyebrow}>Build Phase Control Report</Text>
          <Text style={css.coverTitle}>{project.name}</Text>
          <Text style={css.locationPill}>⌖ {project.location || "—"}</Text>
        </View>
        <View style={css.coverBottom}>
          <View>
            <Text style={css.statLabel}>Overall Progress</Text>
            <Text style={css.statValue}>{overallProgress}%</Text>
          </View>
          <View>
            <Text style={css.statLabel}>Tasks Completed</Text>
            <Text style={css.statValue}>{completedCount}<Text style={{ fontSize: 16, color: "rgba(255,255,255,0.35)" }}>/{totalTasks}</Text></Text>
          </View>
          <View>
            <Text style={css.statLabel}>Days to Opening</Text>
            <Text style={css.statValue}>{daysRemaining !== null ? daysRemaining : "—"}</Text>
            {daysRemaining !== null && <Text style={css.statNote}>{formatDate(project.openingDate, { day: "numeric", month: "long" })}</Text>}
          </View>
        </View>
      </View>
      <Text style={css.coverMeta}>Prepared on {getReportDate()} · {project.name} · {project.location || ""}</Text>
    </Page>
  );
}

function SummaryPage({ project, tasks, overallProgress, completedCount, overdueTasks, daysRemaining }) {
  const totalTasks = tasks.length;
  const taskCompletionPercent = totalTasks ? Math.round((completedCount / totalTasks) * 100) : 0;

  return (
    <Page size="A4" style={css.page}>
      <Text style={css.sectionTitle}>Executive Summary</Text>

      <View style={css.kpiRow}>
        <View style={[css.kpiCard, css.kpiPrimary]}>
          <Text style={[css.kpiLabel, css.kpiPrimaryLabel]}>Days to Opening</Text>
          <Text style={css.kpiValue}>{daysRemaining !== null ? daysRemaining : "—"}</Text>
          <Text style={[css.kpiNote, { color: "rgba(255,255,255,0.5)" }]}>Target: {formatDate(project.openingDate, { day: "numeric", month: "long" })}</Text>
        </View>
        <View style={css.kpiCard}>
          <Text style={css.kpiLabel}>Tasks Completed</Text>
          <Text style={css.kpiValue}>{completedCount}<Text style={{ fontSize: 14, color: "#9aaba6" }}>/{totalTasks}</Text></Text>
          <Text style={css.kpiNote}>{taskCompletionPercent}% of checklist done</Text>
        </View>
        <View style={[css.kpiCard, overdueTasks.length > 0 && css.kpiDanger]}>
          <Text style={css.kpiLabel}>Overdue Tasks</Text>
          <Text style={css.kpiValue}>{overdueTasks.length}</Text>
          <Text style={css.kpiNote}>{overdueTasks.length > 0 ? "Needs immediate attention" : "No delayed tasks"}</Text>
        </View>
        <View style={css.kpiCard}>
          <Text style={css.kpiLabel}>Overall Progress</Text>
          <Text style={css.kpiValue}>{overallProgress}%</Text>
          <Text style={css.kpiNote}>{PHASES.length} phases tracked</Text>
        </View>
      </View>

      {overdueTasks.length > 0 && (
        <View>
          <View style={css.overdueHeader}>
            <Text style={css.overdueHeaderText}>⚠  {overdueTasks.length} Overdue Task{overdueTasks.length !== 1 ? "s" : ""}</Text>
          </View>
          <View style={css.overdueTable}>
            <View style={[css.tableRow, css.tableHeader]}>
              <Text style={[css.th, {flex: 1}]}>Phase</Text>
              <Text style={[css.th, {flex: 2}]}>Task</Text>
              <Text style={[css.th, {flex: 1.2}]}>Owner</Text>
              <Text style={[css.th, {flex: 1.3}]}>Deadline</Text>
              <Text style={[css.th, {flex: 0.7}]}>Progress</Text>
            </View>
            {overdueTasks.map((task, i) => {
              const phase = PHASES.find(p => p.id === task.phase);
              return (
                <View key={i} style={[css.tableRow, i % 2 === 1 && css.tableRowAlt]}>
                  <Text style={[css.td, {flex: 1, fontSize: 9}]}>{phase ? phase.icon + " " + phase.name : "—"}</Text>
                  <Text style={[css.td, {flex: 2, fontWeight: 700, fontSize: 9}]}>{task.title}</Text>
                  <Text style={[css.tdMuted, {flex: 1.2, fontSize: 9}]}>{task.owner || "—"}</Text>
                  <Text style={[css.tdDanger, {flex: 1.3, fontSize: 9}]}>{formatDate(task.deadline, { day: "numeric", month: "short", year: "numeric" })}</Text>
                  <Text style={[css.td, {flex: 0.7, fontWeight: 700, fontSize: 9}]}>{task.progress}%</Text>
                </View>
              );
            })}
          </View>
        </View>
      )}

      <Text style={css.sectionTitle}>Phase Breakdown</Text>
      {PHASES.map(phase => {
        const phaseTasks = tasks.filter(t => t.phase === phase.id);
        const avg = phaseTasks.length
          ? Math.round(phaseTasks.reduce((s, t) => s + Number(t.progress || 0), 0) / phaseTasks.length)
          : 0;
        const deadlines = phaseTasks.map(t => parseLocalDate(t.deadline)).filter(Boolean);
        const targetDate = deadlines.length
          ? formatDate(new Date(Math.max(...deadlines.map(d => d.getTime()))).toISOString(), { day: "numeric", month: "short", year: "numeric" })
          : "Not set";

        return (
          <View key={phase.id} style={css.phaseSection}>
            <View style={css.phaseHeader}>
              <View style={css.phaseLeft}>
                <View style={css.phaseIconBox}><Text style={css.phaseIcon}>{phase.icon}</Text></View>
                <Text style={css.phaseName}>{phase.name}</Text>
              </View>
              <View style={css.phaseMeta}>
                <Text style={css.phaseMetaText}>Target: {targetDate}</Text>
                <Text style={css.phaseProgress}>{avg}%</Text>
              </View>
            </View>
            <View style={css.progressBar}>
              <View style={[css.progressFill, { width: `${avg}%` }]} />
            </View>
            <Text style={css.phaseCount}>{phaseTasks.length} task{phaseTasks.length !== 1 ? "s" : ""}</Text>

            {phaseTasks.length > 0 && (
              <View style={css.taskTable}>
                <View style={[css.tableRow, css.tableHeader]}>
                  <Text style={[css.taskTh, { flex: 1.5 }]}>Owner</Text>
                  <Text style={[css.taskTh, { flex: 3 }]}>Task</Text>
                  <Text style={[css.taskTh, { flex: 1.5 }]}>Deadline</Text>
                  <Text style={[css.taskTh, { flex: 1 }]}>Status</Text>
                  <Text style={[css.taskTh, { flex: 0.8 }]}>Progress</Text>
                </View>
                {phaseTasks
                  .slice().sort((a, b) => String(a.deadline).localeCompare(String(b.deadline)))
                  .map((task, i) => {
                    const s = statusFor(Number(task.progress), task.deadline);
                    const badge = s === "Completed" ? css.badgeOk
                      : s === "Overdue" ? css.badgeDanger
                      : s === "In progress" ? css.badgeProgress
                      : css.badgePending;
                    return (
                      <View key={i} style={[css.tableRow, i % 2 === 1 && css.tableRowAlt]}>
                        <Text style={[css.taskTdMuted, { flex: 1.5, fontSize: 9 }]}>{task.owner || "—"}</Text>
                        <Text style={[css.taskTd, { flex: 3, fontSize: 9 }]}>{task.title}</Text>
                        <Text style={[css.taskTd, { flex: 1.5, fontSize: 9 }]}>{formatDate(task.deadline, { day: "numeric", month: "short", year: "numeric" })}</Text>
                        <View style={{ flex: 1 }}><Text style={badge}>{s}</Text></View>
                        <Text style={[css.taskTd, { flex: 0.8, fontWeight: 700, fontSize: 9 }]}>{task.progress}%</Text>
                      </View>
                    );
                  })}
              </View>
            )}
          </View>
        );
      })}

      <View style={css.footer} fixed>
        <Text style={css.footerText}>{project.name} · Launch Tracker Report</Text>
        <Text style={css.footerText}>Generated {getReportDate()}</Text>
      </View>
    </Page>
  );
}

function MecardeeReport({ project, tasks }) {
  const overallProgress = tasks.length
    ? Math.round(tasks.reduce((s, t) => s + Number(t.progress || 0), 0) / tasks.length)
    : 0;
  const completedCount = tasks.filter(t => Number(t.progress) >= 100).length;
  const overdueTasks = tasks.filter(t => statusFor(Number(t.progress), t.deadline) === "Overdue");
  const openingDate = parseLocalDate(project.openingDate);
  const daysRemaining = openingDate ? Math.max(0, daysBetween(startOfToday(), openingDate)) : null;

  return (
    <Document>
      <CoverPage
        project={project}
        overallProgress={overallProgress}
        completedCount={completedCount}
        totalTasks={tasks.length}
        daysRemaining={daysRemaining}
      />
      <SummaryPage
        project={project}
        tasks={tasks}
        overallProgress={overallProgress}
        completedCount={completedCount}
        overdueTasks={overdueTasks}
        daysRemaining={daysRemaining}
      />
    </Document>
  );
}

export async function GET() {
  try {
    const supabase = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL,
      process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
    );

    const [projectResult, tasksResult] = await Promise.all([
      supabase.from("mecardee_project").select("*").eq("id", 1).maybeSingle(),
      supabase.from("mecardee_tasks").select("*").order("sort_order", { ascending: true }).order("deadline", { ascending: true })
    ]);

    const project = {
      name: String(projectResult?.data?.name || "Mecardee Car Wash"),
      location: String(projectResult?.data?.location || "Kerala, India"),
      openingDate: projectResult?.data?.opening_date || null
    };

    const tasks = (tasksResult.data || []).map(row => ({
      title: String(row.title || "Untitled task"),
      phase: String(row.phase || "site"),
      owner: String(row.owner || ""),
      deadline: row.deadline,
      progress: Number.isFinite(Number(row.progress)) ? Number(row.progress) : 0,
      notes: String(row.notes || "")
    }));

    const pdf = await renderToBuffer(<MecardeeReport project={project} tasks={tasks} />);
    const filename = `mecardee-report-${new Date().toISOString().slice(0, 10)}.pdf`;
    return new NextResponse(pdf, {
      headers: {
        "Content-Type": "application/pdf",
        "Content-Disposition": `attachment; filename="${filename}"`
      }
    });
  } catch (err) {
    console.error("PDF generation failed:", err);
    return NextResponse.json(
      { error: "Failed to generate report", detail: err?.message || String(err) },
      { status: 500 }
    );
  }
}
