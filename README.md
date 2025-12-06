# DevOps-AI-Model-Automatization
Using DevOps techniques to implement an automated CI/CD process for training and versioning AI models: an analysis of the maintenance of AI-based systems compared to manual methods

## Objective of the Thesis:

The objective of this thesis is to analyze the effectiveness of deploying artificial intelligence (AI) models using an automated CI/CD process in containerized and cloud environments, based on DevOps techniques. As part of the project, an infrastructure will be developed to enable automated training, testing, and deployment of AI models. A key element of this work will be assessing the impact of model versioning on performance quality, deployment stability, and resource consumption, with particular emphasis on comparisons to manual model-management methods.

## Tasks:

  1. Present the problems associated with the lack of a consistent versioning system and the difficulties in maintaining reproducible results. Based on this analysis, the necessity of implementing CI/CD automation as an effective solution will be justified.

  2. Provide a technical description of the integration, deployment, and orchestration tools used to build the complete CI/CD pipeline. The work will discuss mechanisms for automatically detecting changes in code or training data, as well as technical details related to AI model versioning. The role of containerization and Kubernetes orchestration in managing the model lifecycle will be highlighted.

  3. Conduct a comparative analysis of the automated CI/CD process versus the manual approach to managing the AI model lifecycle, as well as simplified CI/CD pipelines. The comparison will include aspects such as ease of deployment, the time required to launch a model, system stability, and solution scalability. For each approach, the user will perform a set of standardized tasks, and the results will be compared in tabular form, with particular emphasis on time- and quality-related metrics.

  4. Prepare a test environment in a public cloud (e.g., AWS, Azure) that enables full isolation of model versions using Kubernetes namespaces. Infrastructure and application monitoring tools will be deployed along with visualization of their metrics. The test environment will allow automatic tracking of operational parameters and resource usage by AI models.

  5. Conduct quantitative and qualitative tests of the deployed AI models. The analysis will cover key indicators, including prediction accuracy, hardware resource consumption, and overall system stability. The results will be presented using visualization tools such as Grafana and will serve as a detailed evaluation of the effectiveness of the applied CI/CD approach.

  6. Summarize the conducted research and analyze the test results to assess the efficiency of CI/CD automation compared to traditional approaches to retraining AI models. The conclusions will include a comparison of the strengths and weaknesses of both solutions and indicate potential areas for process optimization, such as automation of model quality testing or improvements in versioning and real-time monitoring mechanisms.

### Polish version below:
Wykorzystanie technik DevOps w implementacji automatycznego procesu CI/CD do uczenia i wersjonowania modeli SI: analiza utrzymania systemów wykorzystujących SI w porównaniu do metod manualnych

## Cel pracy:

Celem pracy jest analiza efektywności wdrażania modeli sztucznej inteligencji (SI) z wykorzystaniem zautomatyzowanego procesu CI/CD w środowiskach skonteneryzowanym oraz chmurowym, bazując na technikach DevOps. W ramach projektu powstanie infrastruktura umożliwiająca automatyczne przeprowadzanie uczenia, testowania oraz wdrażania modeli SI. Kluczowym elementem niniejszej pracy będzie ocena wpływu wersjonowania modeli na jakość ich działania, stabilność wdrożeń oraz zużycie zasobów, kładąc szczególny nacisk na porównanie z manualnymi metodami zarządzania modelami.

## Zadania:
  1.	Przedstawienie problemów związanych z brakiem spójnego systemu wersjonowania oraz trudnościami w utrzymaniu powtarzalności wyników. Na tej podstawie uzasadniona zostanie konieczność wdrożenia automatyzacji CI/CD jako efektywnego rozwiązania.
  
  2.	Opis techniczny narzędzi integracji, wdrażania i orkiestracji wykorzystanych do stworzenia kompleksowego pipeline’u CI/CD. Omówione zostaną mechanizmy automatycznego wykrywania zmian w kodzie lub danych treningowych oraz szczegóły techniczne dotyczące wersjonowania modeli SI. Podkreślona zostanie rola konteneryzacji oraz orkiestracji Kubernetes w zarządzaniu cyklem życia modeli.
  
  3.	Analiza porównawcza zautomatyzowanego procesu CI/CD w stosunku do ręcznego podejścia do zarządzania cyklem życia modeli AI oraz uproszczonych pipeline'ów CI/CD. Porównanie obejmie aspekty takie jak łatwość wdrażania, czas niezbędny na uruchomienie modelu, stabilność systemu oraz skalowalność rozwiązania. Dla każdego z podejść użytkownik wykona zestaw ustandaryzowanych zadań, a następnie porównane zostaną wyniki w ujęciu tabelarycznym, ze szczególnym uwzględnieniem metryk czasowych i jakościowych.
  
  4.	Przygotowanie środowiska testowego w chmurze publicznej (np. AWS, Azure), które pozwoli na pełną izolację wersji modeli dzięki wykorzystaniu namespace’ów w Kubernetes. Wdrożone zostaną narzędzia do monitoringu infrastruktury oraz aplikacji, wraz z wizualizacją ich metryk. Środowisko testowe umożliwi automatyczne śledzenie parametrów działania i zużycia zasobów przez modele SI.
  
  5.	Przeprowadzenie testów ilościowych i jakościowych dla wdrożonych modeli SI. Analiza obejmie kluczowe wskaźniki, w tym skuteczność predykcji, zużycie zasobów sprzętowych oraz stabilności działania całego systemu. Wyniki zostaną przedstawione za pomocą narzędzia do wizualizacji, np. w Grafanie, i posłużą do szczegółowej oceny efektywności zastosowanego podejścia CI/CD.
  
  6.	Podsumowanie przeprowadzonych badań z analizą wyników testów pozwoli ocenić efektywność automatyzacji procesu CI/CD względem tradycyjnego podejścia do ponownego uczenia modeli SI. Wnioski będą uwzględniały porównanie mocnych i słabych stron obu rozwiązań, a także wskazywały potencjalne obszary optymalizacji procesu, np. automatyzację testów jakości modeli czy usprawnienie mechanizmów wersjonowania i monitoringu w czasie rzeczywistym.
