import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/customer360/domain/entities/customer_detail_state.dart';
import 'package:mobile/features/customer360/presentation/providers/customer360_providers.dart';

import '../../helpers/wait_until.dart';
import 'customer360_test_container.dart';
import 'fake_customer_repository.dart';

void main() {
  group('CustomerDetailController', () {
    test('loads the customer profile once the workspace resolves', () async {
      final repo = FakeCustomerRepository()..customerToReturn = testCustomer(name: 'Globex');
      final container = await buildCustomerTestContainer(customerRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, customerDetailControllerProvider('c1')).close);

      await waitUntil(() => container.read(customerDetailControllerProvider('c1')).status == CustomerDetailStatus.success);

      expect(container.read(customerDetailControllerProvider('c1')).customer?.name, 'Globex');
    });

    test('maps a not-found error (missing or non-customer lead) to notFound', () async {
      final repo = FakeCustomerRepository()..getCustomerError = const NotFoundException('Customer not found.');
      final container = await buildCustomerTestContainer(customerRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, customerDetailControllerProvider('c1')).close);

      await waitUntil(() => container.read(customerDetailControllerProvider('c1')).status == CustomerDetailStatus.notFound);
    });

    test('surfaces other errors', () async {
      final repo = FakeCustomerRepository()..getCustomerError = const NetworkException('offline');
      final container = await buildCustomerTestContainer(customerRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, customerDetailControllerProvider('c1')).close);

      await waitUntil(() => container.read(customerDetailControllerProvider('c1')).status == CustomerDetailStatus.error);
      expect(container.read(customerDetailControllerProvider('c1')).errorMessage, 'offline');
    });
  });
}
