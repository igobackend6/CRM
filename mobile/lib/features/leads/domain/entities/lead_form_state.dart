import 'lead.dart';

enum LeadFormStatus { idle, submitting, success, error }

class LeadFormState {
  const LeadFormState._({required this.status, this.lead, this.errorMessage});

  const LeadFormState.idle() : this._(status: LeadFormStatus.idle);
  const LeadFormState.submitting() : this._(status: LeadFormStatus.submitting);
  const LeadFormState.success(Lead lead) : this._(status: LeadFormStatus.success, lead: lead);
  const LeadFormState.error(String message) : this._(status: LeadFormStatus.error, errorMessage: message);

  final LeadFormStatus status;
  final Lead? lead;
  final String? errorMessage;
}
