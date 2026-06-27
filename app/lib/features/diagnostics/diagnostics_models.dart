// Phase 6 diagnostics view models (Section 5.3, Flow C).

/// One uploaded result against an order (in-app viewer: structured / pdf / image).
class TestReportView {
  const TestReportView({
    required this.reportType, // pdf | image | structured
    this.fileUrl,
    this.structuredValues,
    this.uploadedAt,
  });

  final String reportType;
  final String? fileUrl;
  final Map<String, dynamic>? structuredValues;
  final DateTime? uploadedAt;

  factory TestReportView.fromMap(Map<String, dynamic> m) => TestReportView(
        reportType: (m['report_type'] ?? 'structured') as String,
        fileUrl: m['file_url'] as String?,
        structuredValues: (m['structured_values'] as Map?)?.cast<String, dynamic>(),
        uploadedAt: m['uploaded_at'] != null
            ? DateTime.tryParse(m['uploaded_at'].toString())
            : null,
      );
}

/// A test order as seen by the PATIENT or DOCTOR — full order detail + any
/// reports. (The partner side never sees this shape; see [ClaimedOrder].)
class TestOrderView {
  const TestOrderView({
    required this.id,
    required this.testType,
    required this.testName,
    required this.status,
    this.orderCode,
    this.createdAt,
    this.reports = const [],
  });

  final String id;
  final String testType;
  final String testName;
  final String status; // ordered | sample_collected | in_progress | report_ready | cancelled
  final String? orderCode;
  final DateTime? createdAt;
  final List<TestReportView> reports;

  factory TestOrderView.fromMap(Map<String, dynamic> m) => TestOrderView(
        id: m['id'] as String,
        testType: (m['test_type'] ?? '') as String,
        testName: (m['test_name'] ?? '') as String,
        status: (m['status'] ?? 'ordered') as String,
        orderCode: m['order_code'] as String?,
        createdAt: m['created_at'] != null
            ? DateTime.tryParse(m['created_at'].toString())
            : null,
        reports: ((m['test_reports'] ?? const []) as List)
            .map((r) => TestReportView.fromMap((r as Map).cast<String, dynamic>()))
            .toList(),
      );
}

/// The privacy-safe view a diagnostic partner gets on claiming an order code:
/// ONLY name + the one ordered test + ordering doctor/clinic. Never history.
class ClaimedOrder {
  const ClaimedOrder({
    required this.orderId,
    required this.patientName,
    required this.testType,
    required this.testName,
    required this.doctorName,
    required this.clinicName,
    required this.status,
  });

  final String orderId;
  final String patientName;
  final String testType;
  final String testName;
  final String doctorName;
  final String clinicName;
  final String status;

  factory ClaimedOrder.fromMap(Map<String, dynamic> m) => ClaimedOrder(
        orderId: m['order_id'] as String,
        patientName: (m['patient_name'] ?? '') as String,
        testType: (m['test_type'] ?? '') as String,
        testName: (m['test_name'] ?? '') as String,
        doctorName: (m['doctor_name'] ?? '') as String,
        clinicName: (m['clinic_name'] ?? '') as String,
        status: (m['status'] ?? 'ordered') as String,
      );
}

/// One row in a partner's work queue (orders it currently holds a grant for).
class PartnerQueueItem {
  const PartnerQueueItem({
    required this.orderId,
    required this.patientName,
    required this.testType,
    required this.testName,
    required this.status,
    required this.hasReport,
  });

  final String orderId;
  final String patientName;
  final String testType;
  final String testName;
  final String status;
  final bool hasReport;

  factory PartnerQueueItem.fromMap(Map<String, dynamic> m) => PartnerQueueItem(
        orderId: m['order_id'] as String,
        patientName: (m['patient_name'] ?? '') as String,
        testType: (m['test_type'] ?? '') as String,
        testName: (m['test_name'] ?? '') as String,
        status: (m['status'] ?? 'ordered') as String,
        hasReport: (m['has_report'] ?? false) as bool,
      );
}
